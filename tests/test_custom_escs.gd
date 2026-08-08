class_name TestCustomEscs
extends RefCounted
## Builder-entered ESCs (LTHL-25, part A). Read tests/test_custom_frames.gd first: the shape of
## every test here, and the two things above everything else (a custom board cannot silently become
## the reference build, and a half-written user:// document cannot stop Lab from opening), are
## inherited from that suite.
##
## The ESC is the simplest of the six categories — three numbers, a mass and a bolt pattern — and
## it has by some distance the most dangerous single field. escs.json's `_schema` puts it in
## capitals: RATINGS ARE PER MOTOR, NOT PER BOARD. A builder reading "45A 4-in-1" off their own
## product page may type 180, and nothing downstream would complain: the build would simply have an
## ESC four times too strong and would never again be current-limited by it.
##
## So the weight of this suite sits on the per-channel cross-check, asserted from BOTH sides, and
## on the promise that `burst_a` is carried and never used as a limit.

const EPS := 0.05


static func run() -> Array:
	var results: Array = []
	results.append(_test_reference_build_is_out_of_reach())
	results.append(_test_a_colliding_id_is_refused_and_the_catalog_survives())
	results.append(_test_a_whole_board_rating_is_caught_and_a_per_channel_one_is_not())
	results.append(_test_burst_below_continuous_warns())
	results.append(_test_burst_is_not_used_as_a_limit())
	results.append(_test_a_mismatched_esc_pattern_raises_the_stack_fit_warning())
	results.append(_test_a_heavy_esc_adds_exactly_its_excess())
	results.append(_test_a_custom_esc_names_itself_and_quotes_its_source())
	results.append(_test_unknown_fields_survive_a_round_trip())
	results.append(_test_the_refusals_name_what_is_missing())
	return results


# ---------------------------------------------------------------------------
# Scratch and restore, same shape as tests/test_custom_batteries.gd
# ---------------------------------------------------------------------------

static func _scratch(suffix: String) -> String:
	var path := "user://test_custom_escs_%s.json" % suffix
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


## The shed 60 A 4-in-1 the rest of this suite uses. Built through make_record so a change to the
## record's shape cannot leave the tests asserting the old one.
static func _record_60a() -> Dictionary:
	return CustomEscs.make_record("Shed 60A 4in1", 60.0, 70.0, 4, 13.0, "30.5x30.5",
		"3-6S", "DShot600", "off the product page")


static func _find(warnings: Array, id: StringName) -> BuildWarning:
	for warning in warnings:
		if (warning as BuildWarning).id == id:
			return warning
	return null


## A build on a named custom ESC, against a catalog that has the given records merged. Everything
## else is the reference build, so any difference is the board's.
static func _build_on(catalog: PartsCatalog, esc_id: String) -> Build:
	return Build.from_ids(catalog, ReferenceBuild.FRAME_ID, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, esc_id, ReferenceBuild.FC_ID)


## Saves the records to the live document, loads a merged catalog, and hands both to `body` — then
## restores whatever was there before, whether or not the body succeeded.
static func _with_saved(records: Array, body: Callable) -> Variant:
	var previous := ""
	if FileAccess.file_exists(CustomEscs.SAVE_PATH):
		previous = FileAccess.get_file_as_string(CustomEscs.SAVE_PATH)

	var document := CustomEscs.new()
	for record in records:
		document.add(record)
	document.save(CustomEscs.SAVE_PATH)

	var result: Variant = body.call(PartsCatalog.load_with_custom())
	_restore(CustomEscs.SAVE_PATH, previous)
	return result


# ---------------------------------------------------------------------------
# The oracles
# ---------------------------------------------------------------------------

## 496 g / 11.69 / 29.6%, asserted here as well as in every other custom-parts suite because THIS
## is the suite that would notice a custom board move it for a custom-ESC reason.
static func _test_reference_build_is_out_of_reach() -> TestResult:
	var seen: bool = _with_saved([CustomEscs.make_record("Reference Impostor ESC", 999.0, 1200.0, 4,
			9999.0, "30.5x30.5", "3-6S", "DShot600", "invented to try to move the oracle")],
		func(merged: PartsCatalog) -> bool:
			return not merged.get_part("custom_reference_impostor_esc").is_empty())

	var build := ReferenceBuild.build()
	var auw := build.all_up_weight_g()
	var twr := build.thrust_to_weight()
	var hover := build.hover_throttle()
	var pinned := absf(auw - 496.0) < EPS and absf(twr - 11.69) < 0.01 and absf(hover - 0.296) < 0.001

	return TestResult.new(
		"a defined custom ESC does not move the reference build's 496 g / 11.69 / 29.6%",
		bool(seen) and pinned,
		"merged sees it=%s, AUW %.2f g, TWR %.2f, hover %.1f%%" % [
			seen, auw, twr, hover * 100.0])


## The landmine, from the document's end. add() and load_from() must BOTH refuse, because a builder
## can hand-edit this file and the file is the thing that reaches the catalog.
static func _test_a_colliding_id_is_refused_and_the_catalog_survives() -> TestResult:
	var path := _scratch("collision")
	_write_raw(path, JSON.stringify({
		"schema": 1,
		"escs": [{
			"part_id": Build.DEFAULT_ESC_ID,
			"name": "Not the reference ESC",
			"category": "esc",
			"mass_g": 999.0,
			"mounting": {"attachment": "bolt", "pattern": "30.5x30.5"},
			"specs": {"continuous_a": 999.0, "burst_a": 1200.0, "channels": 4},
			"source": "hand-edited to try to shadow the reference board",
		}],
	}))

	var document := CustomEscs.load_from(path)
	var refused := document.records().is_empty() and not document.rejections().is_empty()

	var direct := CustomEscs.new().add({
		"part_id": Build.DEFAULT_ESC_ID, "name": "Also not it", "category": "esc",
		"mass_g": 12.0, "mounting": {"attachment": "bolt", "pattern": "30.5x30.5"},
		"specs": {"continuous_a": 45.0, "burst_a": 55.0, "channels": 4}, "source": "x",
	})

	var shipped := PartsCatalog.load_default().get_part(Build.DEFAULT_ESC_ID)
	var intact := absf(float(shipped.get("mass_g", 0.0)) - Build.ESC_BUDGET_MASS_G) < EPS

	_wipe(path)
	return TestResult.new(
		"an ESC claiming a shipped id is refused from the file and from add(), and the shipped board is untouched",
		refused and not direct.is_empty() and intact,
		"file refused=%s (%s), add refused=%s, shipped mass %.1f g" % [
			refused, document.rejections(), not direct.is_empty(),
			float(shipped.get("mass_g", 0.0))])


# ---------------------------------------------------------------------------
# The one real hazard
# ---------------------------------------------------------------------------

## THE test of this half of the slice. A builder who reads "60A 4-in-1" and types the whole-board
## figure enters 240, and the resulting board is four times too strong — silently, because a
## too-strong ESC simply stops being the limiting component and nothing else changes.
##
## Both sides asserted, because a check that fires on everything catches nothing: 240 A must be
## named as the mistake it is, and a plausible 60 A must go through without a murmur.
static func _test_a_whole_board_rating_is_caught_and_a_per_channel_one_is_not() -> TestResult:
	var result: Dictionary = _with_saved([
			_record_60a(),
			CustomEscs.make_record("Shed 240A Mistake", 240.0, 280.0, 4, 13.0, "30.5x30.5",
				"3-6S", "DShot600", "read off the product page as a whole-board figure"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var mistaken := _find(_build_on(merged, "custom_shed_240a_mistake").warnings(),
				&"esc_whole_board_rating")
			var plausible := _find(_build_on(merged, "custom_shed_60a_4in1").warnings(),
				&"esc_whole_board_rating")
			return {
				"mistaken": mistaken != null,
				"names_it": mistaken != null and mistaken.message.contains("whole-board"),
				"quotes_per_channel": mistaken != null and mistaken.message.contains("60"),
				"plausible": plausible != null,
			})

	return TestResult.new(
		"a 4x whole-board ESC rating is caught and named; a plausible per-channel one is not",
		result["mistaken"] and result["names_it"] and result["quotes_per_channel"] \
			and not result["plausible"],
		"240 A warns=%s (names the mistake=%s, quotes 60 A per channel=%s), 60 A warns=%s (want false)" % [
			result["mistaken"], result["names_it"], result["quotes_per_channel"],
			result["plausible"]])


## Incoherent rather than surprising: a burst rating below the continuous one is not a board, it is
## a typo. Warned rather than refused, because labs-and-sim.md §2 warns and never blocks and
## because `burst_a` binds nothing — the aircraft flies exactly the same either way, which is
## precisely why nothing else would ever mention it.
static func _test_burst_below_continuous_warns() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomEscs.make_record("Shed Backwards", 60.0, 40.0, 4, 13.0, "30.5x30.5",
				"3-6S", "DShot600", "burst and continuous entered the wrong way round"),
			_record_60a(),
		],
		func(merged: PartsCatalog) -> Dictionary:
			return {
				"backwards": _find(_build_on(merged, "custom_shed_backwards").warnings(),
					&"esc_burst_below_continuous") != null,
				"ordered": _find(_build_on(merged, "custom_shed_60a_4in1").warnings(),
					&"esc_burst_below_continuous") != null,
			})

	return TestResult.new(
		"an ESC whose burst rating is below its continuous rating warns; a coherent one does not",
		result["backwards"] and not result["ordered"],
		"backwards warns=%s, coherent warns=%s (want false)" % [
			result["backwards"], result["ordered"]])


## The schema's promise, asserted rather than trusted. Two boards identical but for their burst
## rating must produce the same throttle ceiling — if burst ever became a limit, this is the test
## that would say so, and it would say so before anybody's build got quietly faster.
static func _test_burst_is_not_used_as_a_limit() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomEscs.make_record("Shed Modest Burst", 20.0, 22.0, 4, 13.0, "30.5x30.5",
				"3-6S", "DShot600", "off the product page"),
			CustomEscs.make_record("Shed Wild Burst", 20.0, 200.0, 4, 13.0, "30.5x30.5",
				"3-6S", "DShot600", "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var modest := _build_on(merged, "custom_shed_modest_burst")
			var wild := _build_on(merged, "custom_shed_wild_burst")
			return {
				"modest": modest.max_throttle_fraction(),
				"wild": wild.max_throttle_fraction(),
				"limited": modest.limiting_component()["name"],
			})

	# The 20 A board must actually be the binding constraint, or the two agreeing proves nothing
	# except that something else was limiting both.
	var binds: bool = str(result["limited"]) == "esc"
	var same: bool = absf(float(result["modest"]) - float(result["wild"])) < 1e-9

	return TestResult.new(
		"burst_a is carried and never used as a limit: 22 A and 200 A burst give the same throttle ceiling",
		binds and same,
		"ESC is the binding component=%s, modest %.4f vs wild %.4f" % [
			binds, result["modest"], result["wild"]])


# ---------------------------------------------------------------------------
# The shared half — mass, fit, provenance, persistence
# ---------------------------------------------------------------------------

## The existing _stack_fit_warning, reached through a custom board. Tested separately from the FC's
## because they are two call sites with two warning ids, and a test that only exercised one would
## pass with the other wired to nothing.
static func _test_a_mismatched_esc_pattern_raises_the_stack_fit_warning() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomEscs.make_record("Shed 20x20 Board", 35.0, 45.0, 4, 6.0, "20x20",
				"3-6S", "DShot600", "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var warning := _find(_build_on(merged, "custom_shed_20x20_board").warnings(),
				&"stack_mount")
			return {
				"raised": warning != null,
				"names_both": warning != null and warning.message.contains("20x20") \
					and warning.message.contains("30.5x30.5"),
				"reference_clear": _find(ReferenceBuild.build().warnings(), &"stack_mount") == null,
			})

	return TestResult.new(
		"a custom 20x20 ESC on the 30.5x30.5 reference frame raises the ESC's own fit warning",
		result["raised"] and result["names_both"] and result["reference_clear"],
		"raised=%s, names both patterns=%s, reference build clear=%s" % [
			result["raised"], result["names_both"], result["reference_clear"]])


## Mass comes OUT of ELECTRONICS_MASS_G, so a board at exactly the budget changes nothing and a
## heavier one adds exactly its excess. Asserted as a difference rather than as an absolute, which
## is what makes it a statement about the budget rather than about this particular board.
static func _test_a_heavy_esc_adds_exactly_its_excess() -> TestResult:
	var heavy_mass := Build.ESC_BUDGET_MASS_G + 7.0
	var result: Dictionary = _with_saved([
			CustomEscs.make_record("Shed Budget ESC", 45.0, 55.0, 4, Build.ESC_BUDGET_MASS_G,
				"30.5x30.5", "3-6S", "DShot600", "off the product page"),
			CustomEscs.make_record("Shed Heavy ESC", 45.0, 55.0, 4, heavy_mass,
				"30.5x30.5", "3-6S", "DShot600", "off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			return {
				"budget": _build_on(merged, "custom_shed_budget_esc").all_up_weight_g(),
				"heavy": _build_on(merged, "custom_shed_heavy_esc").all_up_weight_g(),
			})

	var at_budget := absf(float(result["budget"]) - 496.0) < EPS
	var excess := float(result["heavy"]) - float(result["budget"])
	var exact := absf(excess - 7.0) < EPS

	return TestResult.new(
		"an ESC at the budget mass leaves the aircraft at 496 g; 7 g over adds exactly 7 g",
		at_budget and exact,
		"at budget %.2f g, heavy %.2f g, difference %.2f g (want 7.00)" % [
			result["budget"], result["heavy"], excess])


## Every custom part carries the custom-provenance warning, and it quotes the builder's own words
## because "where did this number come from" is the question the warning exists to answer.
static func _test_a_custom_esc_names_itself_and_quotes_its_source() -> TestResult:
	var result: Dictionary = _with_saved([
			CustomEscs.make_record("Shed Sourced ESC", 45.0, 55.0, 4, 12.0, "30.5x30.5",
				"3-6S", "DShot600", "measured on my kitchen scale, ratings off the product page"),
		],
		func(merged: PartsCatalog) -> Dictionary:
			var warning := _find(_build_on(merged, "custom_shed_sourced_esc").warnings(),
				&"custom_esc")
			return {
				"raised": warning != null,
				"quotes_source": warning != null and warning.message.contains("kitchen scale"),
				# Case-insensitive: the message shouts PER CHANNEL, and this asserts that it is
				# said, not how loudly.
				"says_per_channel": warning != null \
					and warning.message.to_lower().contains("per channel"),
				"characteristic": warning != null \
					and warning.severity == BuildWarning.Severity.CHARACTERISTIC,
				"reference_clear": _find(ReferenceBuild.build().warnings(), &"custom_esc") == null,
			})

	return TestResult.new(
		"a custom-ESC build warns, quotes its provenance and restates the per-channel reading; a catalog build does not",
		result["raised"] and result["quotes_source"] and result["says_per_channel"] \
			and result["characteristic"] and result["reference_clear"],
		"raised=%s, quotes source=%s, says per channel=%s, characteristic=%s, reference clear=%s" % [
			result["raised"], result["quotes_source"], result["says_per_channel"],
			result["characteristic"], result["reference_clear"]])


## A field this version does not know about survives being read and written again. That is what
## lets an older Lothal open a newer document without eating the parts of it it cannot use — and it
## is the same promise CustomParts makes about neighbouring top-level blocks.
static func _test_unknown_fields_survive_a_round_trip() -> TestResult:
	var path := _scratch("unknown")
	var record := _record_60a()
	record["specs"]["telemetry_protocol"] = "KISS"
	record["future_block"] = {"anything": [1, 2, 3]}

	var document := CustomEscs.new()
	var problems := document.add(record)
	document.save(path)

	var reloaded := CustomEscs.load_from(path)
	var stored := reloaded.get_esc("custom_shed_60a_4in1")
	var kept_spec: bool = str(stored.get("specs", {}).get("telemetry_protocol", "")) == "KISS"
	# Compared as floats: JSON has one number type, so [1, 2, 3] comes back as [1.0, 2.0, 3.0].
	# Asserting the ints would be asserting a property of GDScript's parser, not of persistence.
	var kept_block: bool = Array(stored.get("future_block", {}).get("anything", [])) \
		.map(func(value: Variant) -> float: return float(value)) == [1.0, 2.0, 3.0]

	_wipe(path)
	return TestResult.new(
		"a field this version does not know about survives a save and load",
		problems.is_empty() and kept_spec and kept_block,
		"accepted=%s, unknown spec kept=%s, unknown block kept=%s" % [
			problems.is_empty(), kept_spec, kept_block])


## The refusals, which are only defensible where the alternative is silence. A board with no
## continuous rating is not a strange board — it is a board the current model reads as unlimited.
static func _test_the_refusals_name_what_is_missing() -> TestResult:
	var no_rating := CustomEscs.new().add(CustomEscs.make_record("No Rating", 0.0, 55.0, 4, 12.0,
		"30.5x30.5", "3-6S", "DShot600", "off the product page"))
	var no_channels := CustomEscs.new().add(CustomEscs.make_record("No Channels", 45.0, 55.0, 0,
		12.0, "30.5x30.5", "3-6S", "DShot600", "off the product page"))
	var no_pattern := CustomEscs.new().add(CustomEscs.make_record("No Pattern", 45.0, 55.0, 4,
		12.0, "", "3-6S", "DShot600", "off the product page"))
	var good := CustomEscs.new().add(_record_60a())

	var names := func(problems: Array[String], needle: String) -> bool:
		for problem in problems:
			if problem.contains(needle):
				return true
		return false

	var all_named: bool = names.call(no_rating, "continuous_a") \
		and names.call(no_channels, "channels") \
		and names.call(no_pattern, "pattern")

	return TestResult.new(
		"an ESC with no rating, no channels or no bolt pattern is refused by name; a complete one is accepted",
		all_named and good.is_empty(),
		"no rating=%s, no channels=%s, no pattern=%s, good accepted=%s" % [
			no_rating, no_channels, no_pattern, good.is_empty()])
