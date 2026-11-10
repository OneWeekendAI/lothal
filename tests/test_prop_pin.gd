class_name TestPropPin
extends RefCounted
## PD0's pin: no prop-designer slice may move a shelf prop's figures. Bit-exact on macOS, where the
## fixture was written; within 1e-9 elsewhere, because CI's Linux and Windows libm round atan and pow
## differently in the last place and that is not a physics change.
##
## RE-PINNED 2026-11-11 (SR9 mapper class change, commits 477e2dc, 9bbea87): mapper_prop_94x53 on mapper only (figures and bits). The mapper class now flies
## motor_2807_1300kv on a 4S2P 10Ah 580 g pack at c_rating 5: AUW 1145.9 -> 1261.9 g, hover 0.652 -> 0.329, flight 67.8 -> 33.0 min, T:W 4.59; props' aero unchanged.
## RE-PINNED 2026-11-10 (SR1.3): prop_16x12x4 on tiny_whoop top_speed_kmh 111.6456 -> 111.2094 (figures and bits). The tiny whoop is
## thrust-limited (reachable T:W 1.2) and top_speed_kmh() now trims the real lean with directional drag; nothing else moved.
## RE-PINNED 2026-11-09 (SR1-SR2 forward-flight physics; hover and every static/direct solve are bit-identical, so nothing about
## hover moved). Only three groups of keys moved, each for a named reason:
##  - power_ratio_*: rear-rotor interference (rpm-independent window in wake skew; +1.49 % at mu 0.05, +9.55 % at mu 0.1-0.2, +5.97 % at
##    mu 0.3, identical on every prop: exactly 1 + w * 0.5 * (0.89^-1.5 - 1)) and, at edgewise mu 0.2, profile-power growth
##    (1 + 4.65 mu^2)/(1 + 2 mu^2), which lifts the edgewise points to +15.0..+16.3 %.
##  - thrust_ratio_0.00_0.20 (+12..+54 %), _0.05_0.00 and _0.10_0.10 (<= 0.3 %): the ratio is no longer clamped to 1.0, so the edgewise
##    term (translational lift) now shows.
##  - flight_time_min: the freestyle profile is forward flight, so it pays the interference and profile terms and the directional drag
##    and gains the translational lift. -24 % .. +2.6 %; the table is in the sim-reality plan (SR-green section).
## TO MAKE THIS FAIL: change POLAR_C_D0 in rust/src/bemt.rs by 1 %. Every prop goes red.

const OTHER_OS_RELATIVE := 1e-9


static func run() -> Array:
	var results: Array = []
	var fixture: Dictionary = JsonStore.read_document(PropPresetFigures.FIXTURE)
	var shelf := PropPresetFigures.shelf_ids()
	results.append(TestResult.new("prop pin: covers exactly the 21 shelf props",
		shelf.size() == 21 and fixture.size() == 21 and _same_ids(shelf, fixture),
		"shelf %d, fixture %d" % [shelf.size(), fixture.size()]))
	results.append(_comparator_can_fail())
	var catalog := PartsCatalog.load_default()
	for id in shelf:
		if not fixture.has(id):
			continue
		results.append(_prop_is_pinned(id, fixture[id], catalog))
	results.append(_shelf_chords_say_assumed(shelf, catalog))
	return results


static func _same_ids(shelf: Array[String], fixture: Dictionary) -> bool:
	for id in shelf:
		if not fixture.has(id):
			return false
	return true


static func _differs(live: float, pinned: float, pinned_bits: String, exact: bool) -> bool:
	if exact:
		return PropPresetFigures.bits_of(live) != pinned_bits
	return absf(live - pinned) > OTHER_OS_RELATIVE * maxf(absf(pinned), 1e-30)


## One ulp must count as a change on the exact path, or "bit-identical" is a claim about nothing.
static func _comparator_can_fail() -> TestResult:
	var v := 0.1234
	var bytes := PackedFloat64Array([v]).to_byte_array()
	bytes[0] = bytes[0] ^ 1
	var nudged := bytes.to_float64_array()[0]
	var bits := PropPresetFigures.bits_of(v)
	var ok := _differs(nudged, v, bits, true) and not _differs(v, v, bits, true) \
		and _differs(v * 1.000001, v, bits, false) and not _differs(v, v, bits, false)
	return TestResult.new("prop pin: comparator sees one ulp and passes an equal value", ok, "")


static func _prop_is_pinned(id: String, pinned: Dictionary, catalog: PartsCatalog) -> TestResult:
	var live := PropPresetFigures.figures_of(id, catalog)
	var exact := OS.get_name() == "macOS"
	var figures: Dictionary = pinned["figures"]
	var moved: Array[String] = []
	if live.size() != figures.size():
		moved.append("field count %d vs %d" % [live.size(), figures.size()])
	for k in figures:
		if not live.has(k):
			moved.append(k + " missing")
		elif _differs(float(live[k]), float(figures[k]), String(pinned["bits"][k]), exact):
			moved.append("%s %s -> %s" % [k, figures[k], live[k]])
	# A pin over zeros would hold through anything that refuses, so the figures must be real.
	var live_real: bool = float(live["k_t"]) > 0.0 and float(live["flight_time_min"]) > 0.0 \
		and float(live["thrust_to_weight"]) > 1.0
	return TestResult.new("prop pin: %s unmoved on %s" % [id, pinned["class"]],
		moved.is_empty() and live_real, ", ".join(moved.slice(0, 3)))


static func _shelf_chords_say_assumed(shelf: Array[String], catalog: PartsCatalog) -> TestResult:
	var wrong: Array[String] = []
	for id in shelf:
		if not PropellerDocument.from_catalog_prop(catalog.get_part(id)).chord_is_assumed:
			wrong.append(id)
	return TestResult.new("prop pin: every shelf planform is flagged assumed", wrong.is_empty(),
		", ".join(wrong))
