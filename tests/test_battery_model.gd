class_name TestBatteryModel
extends RefCounted
## The pack's open-circuit voltage as a function of how empty it is (physics.md §5).
##
## Until this slice `voltage_live(I) = nominal_v - I*R`, so resting voltage was a constant: a pack
## at 5% read the same open-circuit voltage as a full one. Every consequence of that was invisible
## while nothing plotted voltage over a sustained load. The battery bench plots exactly that, and a
## flat baseline is the first thing anyone would notice.
##
## The assertions are deliberately in two groups, because they defend two different things and
## conflating them would let one hide behind the other.
##
## THE IDENTITY AT FULL CHARGE is its own group, and it is the load-bearing one. The reference
## build's 11.7:1 and 29% hover are FULL-PACK figures, quoted at nominal voltage the way every
## manufacturer thrust table quotes them. The state-of-charge term must therefore be exactly zero
## — not small, not within a tolerance, zero — at used_mah = 0, or this slice silently moves the
## project's own fixed points and no two builders can compare anything again.
##
## THE SHAPE is the second group: a plateau across the flat middle and a knee below ~20%, with
## Li-ion's differently-shaped curve distinguishable from LiPo's. A straight line from full to
## empty would satisfy every "voltage falls as it empties" check anyone would think to write, and
## it would throw away the one behaviour that matters — the knee is what turns "the pack is
## getting low" into "the pack has stopped".

## Where the knee is taken to start, for the shape assertions. Not a model constant: the model has
## no threshold in it, the knee is what the curve does. This is the test's own reading of it.
const KNEE_SOC := 0.20

static func run() -> Array:
	var results: Array = []

	results.append_array(_test_zero_at_full_charge())
	results.append_array(_test_it_falls_as_the_pack_empties())
	results.append_array(_test_the_shape_is_plateau_then_knee())
	results.append_array(_test_chemistry_changes_the_curve())
	results.append_array(_test_the_oracles_have_not_moved())

	return results


static func _pack(chemistry: String = "LiPo") -> BatteryModel:
	return BatteryModel.new(14.8, 0.015, 1500.0, 4, chemistry)


## Puts a pack at a given state of charge, 1.0 = full.
static func _at_soc(pack: BatteryModel, soc: float) -> BatteryModel:
	pack.used_mah = pack.capacity_mah * (1.0 - soc)
	return pack


# ---------------------------------------------------------------------------
# Group one: the identity at full charge
# ---------------------------------------------------------------------------

## Exactly zero, tested as an exact equality rather than as an approximation. A state-of-charge
## term that were merely tiny at full charge would pass an is_equal_approx and still move the
## fourth significant figure of every number the project quotes.
static func _test_zero_at_full_charge() -> Array:
	var results: Array = []

	for chemistry in ["LiPo", "Li-ion"]:
		var pack := _pack(chemistry)
		results.append(TestResult.new(
			"a full %s pack rests at exactly its nominal voltage, to the bit" % chemistry,
			pack.used_mah == 0.0 and pack.resting_voltage_v() == pack.nominal_v,
			"resting %.17f V vs nominal %.17f V" % [pack.resting_voltage_v(), pack.nominal_v]
		))

		# ...and therefore voltage_live returns precisely what it returned before this slice:
		# nominal_v - I*R, with nothing else in it.
		var full := _pack(chemistry)
		var matches := true
		for current_a in [0.0, 1.0, 10.0, 41.5, 120.0]:
			if full.voltage_live(current_a) != full.nominal_v - current_a * full.internal_r_ohm:
				matches = false
		results.append(TestResult.new(
			"at full charge a %s pack's live voltage is still exactly nominal_v - I*R" % chemistry,
			matches,
			"checked 5 currents from 0 to 120 A against the pre-slice expression"
		))

	return results


# ---------------------------------------------------------------------------
# Group two: the curve
# ---------------------------------------------------------------------------

static func _test_it_falls_as_the_pack_empties() -> Array:
	var results: Array = []
	var pack := _pack()

	# Monotonic, sampled finely. The failure this catches is not "it does not fall" — it is a
	# curve with a bump in it, which a piecewise fit through hand-entered knots can acquire from
	# a single mistyped digit and which nothing else here would see.
	var falling := true
	var previous := _at_soc(pack, 1.0).resting_voltage_v()
	for i in range(1, 201):
		var soc := 1.0 - float(i) / 200.0
		var v := _at_soc(pack, soc).resting_voltage_v()
		if v > previous + 1e-9:
			falling = false
		previous = v
	results.append(TestResult.new(
		"resting voltage falls monotonically from full to empty, with no bump anywhere in it",
		falling,
		"200 samples: %.2f V full -> %.2f V empty" % [
			_at_soc(_pack(), 1.0).resting_voltage_v(), _at_soc(_pack(), 0.0).resting_voltage_v()]
	))

	# The magnitude has to be real rather than decorative. A 4S pack that fell by 200 mV across a
	# whole discharge would be monotonic, plateaued, kneed and useless.
	var full_v := _at_soc(_pack(), 1.0).resting_voltage_v()
	var empty_v := _at_soc(_pack(), 0.0).resting_voltage_v()
	var per_cell_drop := (full_v - empty_v) / 4.0
	results.append(TestResult.new(
		"a cell falls about a volt from full to empty, which is what a real one does",
		per_cell_drop > 0.9 and per_cell_drop < 1.5,
		"%.2f V per cell over the whole discharge (%.2f V -> %.2f V at the pack)" % [
			per_cell_drop, full_v, empty_v]
	))

	# Sag is still sag: the state-of-charge term shifts the baseline the load pulls down FROM,
	# and does not replace it. A half-empty pack under load must read lower than a half-empty
	# pack at rest by exactly I*R.
	var half := _at_soc(_pack(), 0.5)
	results.append(TestResult.new(
		"the state-of-charge term moves the baseline and leaves I*R sag doing its own job",
		is_equal_approx(half.resting_voltage_v() - half.voltage_live(40.0), 40.0 * half.internal_r_ohm),
		"at 50%%: rest %.2f V, under 40 A %.2f V, gap %.3f V" % [
			half.resting_voltage_v(), half.voltage_live(40.0),
			half.resting_voltage_v() - half.voltage_live(40.0)]
	))

	return results


## The behaviour that matters, and the one a straight line would throw away. A knee means the
## curve is much steeper below KNEE_SOC than across the middle — so the check is a RATIO of two
## measured slopes, not a value read off a table. A linear model scores 1.0 here and fails.
static func _test_the_shape_is_plateau_then_knee() -> Array:
	var results: Array = []

	for chemistry in ["LiPo", "Li-ion"]:
		var plateau_slope := _slope_v_per_soc(chemistry, 0.35, 0.75)
		var knee_slope := _slope_v_per_soc(chemistry, 0.02, KNEE_SOC)

		results.append(TestResult.new(
			"a %s pack knees down below %.0f%% rather than falling in a straight line" % [
				chemistry, KNEE_SOC * 100.0],
			knee_slope > plateau_slope * 2.5,
			"knee %.2f V per unit SoC vs plateau %.2f — %.1fx steeper" % [
				knee_slope, plateau_slope, knee_slope / plateau_slope]
		))

		# ...and the middle really is a plateau, not merely the shallower half of a straight
		# line. Measured as the fraction of the whole discharge's voltage drop that the middle
		# 40% of the capacity accounts for: on a straight line that is 40%, on a real curve
		# much less.
		var pack := _pack(chemistry)
		var whole_drop := _at_soc(pack, 1.0).resting_voltage_v() - _at_soc(pack, 0.0).resting_voltage_v()
		var middle_drop := _at_soc(pack, 0.75).resting_voltage_v() - _at_soc(pack, 0.35).resting_voltage_v()
		results.append(TestResult.new(
			"the middle of a %s discharge is a plateau, not the shallow half of a straight line" % chemistry,
			middle_drop / whole_drop < 0.25,
			"the middle 40%% of the capacity accounts for %.0f%% of the voltage drop (a line would be 40%%)" % [
				middle_drop / whole_drop * 100.0]
		))

	return results


static func _slope_v_per_soc(chemistry: String, soc_low: float, soc_high: float) -> float:
	var pack := _pack(chemistry)
	var high := _at_soc(pack, soc_high).resting_voltage_v()
	var low := _at_soc(pack, soc_low).resting_voltage_v()
	return (high - low) / (soc_high - soc_low)


## Li-ion is in the catalog because it is not a big LiPo, and the discharge curve is half of why.
## If the two chemistries shared a curve, `chemistry` would not be a physics-bearing spec and it
## would belong in the catalog block after all — so this assertion is also what justifies where
## that field lives.
static func _test_chemistry_changes_the_curve() -> Array:
	var results: Array = []

	var differences: Array = []
	var differ := false
	for soc in [0.9, 0.7, 0.5, 0.3, 0.1]:
		var lipo := _at_soc(_pack("LiPo"), soc).resting_voltage_v()
		var liion := _at_soc(_pack("Li-ion"), soc).resting_voltage_v()
		if absf(lipo - liion) > 0.05:
			differ = true
		differences.append("%.0f%%: %.2f vs %.2f" % [soc * 100.0, lipo, liion])
	results.append(TestResult.new(
		"a Li-ion pack does not rest where a LiPo of the same cell count rests",
		differ,
		"; ".join(differences)
	))

	# Both start from the same place, because both start from nominal_v — which is the whole
	# content of the zero-at-full-charge constraint, restated across chemistries.
	results.append(TestResult.new(
		"both chemistries still rest at exactly nominal voltage when full",
		_pack("LiPo").resting_voltage_v() == _pack("Li-ion").resting_voltage_v(),
		"%.2f V both" % _pack("LiPo").resting_voltage_v()
	))

	# An unrecognised chemistry must fall back to a curve rather than to a flat line or a crash.
	# batteries.json is contributor-editable and a typo there must not silently delete the model.
	var unknown := BatteryModel.new(14.8, 0.015, 1500.0, 4, "Unobtainium")
	var unknown_full := _at_soc(unknown, 1.0).resting_voltage_v()
	var unknown_empty := _at_soc(unknown, 0.0).resting_voltage_v()
	results.append(TestResult.new(
		"a chemistry nobody has heard of still gets a curve, not a flat line",
		unknown_full == 14.8 and unknown_empty < unknown_full - 3.0,
		"%.2f V full -> %.2f V empty" % [unknown_full, unknown_empty]
	))

	return results


# ---------------------------------------------------------------------------
# The fixed points, restated where the change could move them
# ---------------------------------------------------------------------------

## test_hover.gd and test_parts_system.gd already assert 11.7:1 and 29%. This asserts the REASON
## they have not moved, which is a different claim: that the build's electrical starting point is
## bit-identical to what it was before the curve existed. A tolerance-based oracle check can
## absorb a small error here; this cannot.
static func _test_the_oracles_have_not_moved() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var pack := build.battery_model()

	results.append(TestResult.new(
		"the reference build's pack is constructed full, so its bench figures are full-pack figures",
		pack.used_mah == 0.0 and pack.resting_voltage_v() == float(build.battery["specs"]["nominal_v"]),
		"%.2f V resting at %.0f mAh used" % [pack.resting_voltage_v(), pack.used_mah]
	))

	# Build solves its analytic numbers against nominal_v directly rather than through the pack,
	# which is correct — they are spec-sheet figures — and this pins the two to agree at full
	# charge so the analytic path cannot quietly drift away from the dynamic one.
	results.append(TestResult.new(
		"Build's analytic voltage and the pack's resting voltage agree at full charge",
		build.rpm_at_throttle(0.5) > 0.0
			and pack.voltage_live(0.0) == float(build.battery["specs"]["nominal_v"]),
		"open-circuit %.3f V against the catalog's %.3f V" % [
			pack.voltage_live(0.0), float(build.battery["specs"]["nominal_v"])]
	))

	return results
