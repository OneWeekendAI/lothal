class_name TestBatteryModel
extends RefCounted
## The pack's open-circuit voltage as a function of how empty it is (physics.md §5).
##
## Until this slice `voltage_live(I) = nominal_v - I*R`, so resting voltage was a constant: a pack
## at 5% read the same open-circuit voltage as a full one. Every consequence of that was invisible
## while nothing plotted voltage over a sustained load. The battery bench plots exactly that, and a
## flat baseline is the first thing anyone would notice.
##
## The assertions are in groups, because they defend different things and conflating them would
## let one hide behind the other.
##
## THE DATUM is the load-bearing group. `nominal_v` is the voltage the pack rests at partway down
## its discharge, not the voltage it leaves the charger at, so the state-of-charge term is exactly
## zero AT THE NOMINAL POINT and signed either side of it. That is the identity this file pins,
## and it is stated as an exact equality rather than a tolerance for the same reason it always
## was: the reference build's 11.7:1 and 29% are quoted at nominal voltage, the way every
## manufacturer's thrust table and every spec sheet quotes them, and a term that were merely tiny
## at the datum would still move the fourth significant figure of every number Lothal reports.
##
## This REPLACED an identity at full charge. Until this slice `nominal_v` was treated as the
## resting voltage of a FULL pack, which made the term vanish where the oracles are quoted but put
## the whole curve half a volt per cell too low — a 4S rested at 13.16 V at half charge instead of
## 15.16 V, and the aircraft sank out of the sky on a half-used battery. The oracles did not have
## to move to fix it, because they were never full-pack figures: they are nominal-voltage figures,
## and nominal voltage is exactly what the datum now is. See src/sim/battery_model.gd's header.
##
## THE PUBLISHED TABLE is the group that stops the datum from being re-derived from whatever the
## code happens to do. Real per-cell resting voltages, written down here, checked against the pack.
##
## THE SHAPE is the third: a plateau across the flat middle and a knee below ~20%, with Li-ion's
## differently-shaped curve distinguishable from LiPo's. A straight line from full to empty would
## satisfy every "voltage falls as it empties" check anyone would think to write, and it would
## throw away the one behaviour that matters — the knee is what turns "the pack is getting low"
## into "the pack has stopped".

## Where the knee is taken to start, for the shape assertions. Not a model constant: the model has
## no threshold in it, the knee is what the curve does. This is the test's own reading of it.
const KNEE_SOC := 0.20

## Published class-typical LiPo resting voltages per cell, state of charge -> volts. Written down
## here, from the resting-voltage tables physics.md §5 cites, rather than read out of
## BatteryModel.CURVES — the point of this group is to be a second opinion about what a real cell
## does, and a copy of the model's own knots would be no opinion at all.
const PUBLISHED_LIPO_CELL_V := {
	1.00: 4.20, 0.90: 4.08, 0.80: 3.97, 0.70: 3.87, 0.60: 3.83,
	0.50: 3.79, 0.40: 3.75, 0.30: 3.70, 0.20: 3.63, 0.10: 3.50, 0.00: 3.27,
}

## The same for a Li-ion 18650/21700 cell, which rests lower through the middle and has a longer,
## softer tail. Half of why `chemistry` is a physics-bearing spec.
const PUBLISHED_LIION_CELL_V := {
	1.00: 4.20, 0.90: 4.03, 0.80: 3.88, 0.70: 3.78, 0.60: 3.70,
	0.50: 3.63, 0.40: 3.57, 0.30: 3.50, 0.20: 3.40, 0.10: 3.22, 0.00: 2.80,
}

## How far the model may sit from the published figure, per cell. A resting-voltage table is a
## class-typical curve rather than a measurement of one cell, and real packs of the same chemistry
## differ by more than this between brands — so a tighter bound would be asserting a precision
## neither the table nor the model has. It is still far tighter than the 0.50 V/cell error the old
## datum carried, which is the error this bound exists to catch.
const CELL_TOLERANCE_V := 0.05

static func run() -> Array:
	var results: Array = []

	results.append_array(_test_the_nominal_datum())
	results.append_array(_test_it_matches_the_published_tables())
	results.append_array(_test_it_falls_as_the_pack_empties())
	results.append_array(_test_the_shape_is_plateau_then_knee())
	results.append_array(_test_chemistry_changes_the_curve())
	results.append_array(_test_the_oracles_have_not_moved())

	return results


static func _pack(chemistry: String = "LiPo") -> BatteryModel:
	return BatteryModel.create(14.8, 0.015, 1500.0, 4, chemistry)


## Puts a pack at a given state of charge, 1.0 = full.
static func _at_soc(pack: BatteryModel, soc: float) -> BatteryModel:
	pack.used_mah = pack.capacity_mah * (1.0 - soc)
	return pack


# ---------------------------------------------------------------------------
# Group one: the datum. Nominal voltage is an operating point, not full charge.
# ---------------------------------------------------------------------------

## THE STATED DATUM IS NOMINAL VOLTAGE. Everything below says so from a different direction.
static func _test_the_nominal_datum() -> Array:
	var results: Array = []

	for chemistry in ["LiPo", "Li-ion"]:
		var nominal_cell_v: float = BatteryModel.nominal_cell_v(chemistry)

		# The curve has to pass through the chemistry's own nominal cell voltage, or `nominal_v`
		# in batteries.json means something slightly different from what the curve thinks it
		# means and the datum is two numbers instead of one.
		var soc_at_nominal := _soc_where_cell_rests_at(chemistry, nominal_cell_v)
		results.append(TestResult.new(
			"a %s cell's curve passes through its published %.2f V nominal, at %.0f%% charge" % [
				chemistry, nominal_cell_v, soc_at_nominal * 100.0],
			soc_at_nominal > 0.0 and soc_at_nominal < 1.0,
			"nominal is %.0f%% of the way down this chemistry's discharge" % (soc_at_nominal * 100.0)
		))

		# ...and AT that state of charge the pack rests at exactly its nominal voltage. This is the
		# identity the 11.7:1 and 29% oracles are defined at, and it is an exact equality rather
		# than a tolerance for the same reason it was before the datum moved.
		var at_nominal := _at_soc(_pack(chemistry), soc_at_nominal)
		results.append(TestResult.new(
			"a %s pack at its nominal state of charge rests at exactly nominal_v, to the bit" % chemistry,
			at_nominal.soc_offset_v() == 0.0 and at_nominal.resting_voltage_v() == at_nominal.nominal_v,
			"resting %.17f V vs nominal %.17f V" % [
				at_nominal.resting_voltage_v(), at_nominal.nominal_v]
		))

		# ...and at that state of charge, and only there, voltage_live is exactly the pre-curve
		# expression nominal_v - I*R.
		var matches := true
		for current_a in [0.0, 1.0, 10.0, 41.5, 120.0]:
			var p := _at_soc(_pack(chemistry), soc_at_nominal)
			if p.voltage_live(current_a) != p.nominal_v - current_a * p.internal_r_ohm:
				matches = false
		results.append(TestResult.new(
			"at the nominal datum a %s pack's live voltage is exactly nominal_v - I*R" % chemistry,
			matches,
			"checked 5 currents from 0 to 120 A at %.0f%% charge" % (soc_at_nominal * 100.0)
		))

		# The sign either side is the whole change. A full pack is ABOVE nominal — which is why a
		# fresh battery punches harder than the spec sheet — and an empty one is below.
		var full := _at_soc(_pack(chemistry), 1.0)
		var empty := _at_soc(_pack(chemistry), 0.0)
		results.append(TestResult.new(
			"a full %s pack rests ABOVE nominal and a flat one below, which is what a real one does" % chemistry,
			full.soc_offset_v() > 0.0 and empty.soc_offset_v() < 0.0,
			"full %.2f V, nominal %.2f V, empty %.2f V" % [
				full.resting_voltage_v(), full.nominal_v, empty.resting_voltage_v()]
		))

	return results


## The state of charge at which one cell of `chemistry` rests at `target_v`, by bisection on the
## curve. Found rather than written down, because where nominal sits on the discharge is a
## property of the curve's shape — around 30% for a LiPo and around 45% for a Li-ion — and
## hard-coding it here would be a fourth place the datum is stated.
static func _soc_where_cell_rests_at(chemistry: String, target_v: float) -> float:
	var low := 0.0
	var high := 1.0
	for _i in 200:
		var mid := (low + high) * 0.5
		if BatteryModel.cell_open_circuit_v(mid, chemistry) < target_v:
			low = mid
		else:
			high = mid
	return high


# ---------------------------------------------------------------------------
# Group two: the published resting tables
# ---------------------------------------------------------------------------

## The pack must rest where a real one of that many cells rests — cells x the published per-cell
## figure, at every state of charge in the table. This is the assertion the old datum failed by
## half a volt per cell all the way down, and it is anchored to written-down real numbers rather
## than to anything the code produces, so it cannot be satisfied by a model that is merely
## self-consistent.
static func _test_it_matches_the_published_tables() -> Array:
	var results: Array = []

	# Each chemistry is checked on a pack labelled the way the real product is labelled: a 4S LiPo
	# says 14.8 V on the wrapper and a 4S Li-ion says 14.4 V, because their cells' nominals differ.
	# Using one fixture voltage for both would be checking a pack that does not exist, and would
	# fail this group by exactly the 0.1 V/cell the two labels differ by.
	for entry in [["LiPo", 14.8, PUBLISHED_LIPO_CELL_V], ["Li-ion", 14.4, PUBLISHED_LIION_CELL_V]]:
		var chemistry: String = entry[0]
		var label_v: float = entry[1]
		var table: Dictionary = entry[2]
		var worst_error := 0.0
		var worst_soc := 0.0
		for soc in table:
			var pack := _at_soc(BatteryModel.create(label_v, 0.015, 1500.0, 4, chemistry), float(soc))
			var expected_pack_v := float(table[soc]) * float(pack.cells)
			var error_per_cell: float = absf(pack.resting_voltage_v() - expected_pack_v) / float(pack.cells)
			if error_per_cell > worst_error:
				worst_error = error_per_cell
				worst_soc = float(soc)

		results.append(TestResult.new(
			"a %.1f V 4S %s pack rests within %.0f mV/cell of the published table at every state of charge" % [
				label_v, chemistry, CELL_TOLERANCE_V * 1000.0],
			worst_error < CELL_TOLERANCE_V,
			"worst is %.0f mV/cell at %.0f%% charge, across %d points" % [
				worst_error * 1000.0, worst_soc * 100.0, table.size()]
		))

	# The headline number from the bug report, stated on its own so a failure names the symptom
	# rather than a worst-case across a table. A real 4S LiPo at half charge sits at 3.79 V/cell,
	# which is 15.16 V — above its 14.8 V nominal, not the 13.16 V the old datum produced.
	var half := _at_soc(_pack("LiPo"), 0.5)
	results.append(TestResult.new(
		"a 4S LiPo at 50% rests near 15.2 V, not near 13.2 V",
		absf(half.resting_voltage_v() - 15.16) < 4.0 * CELL_TOLERANCE_V,
		"%.2f V against the published 4 x 3.79 = 15.16 V" % half.resting_voltage_v()
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

	# The two chemistries no longer meet at full charge, and that is the datum change showing its
	# working: both fixtures are given the same 14.8 V nominal, but a Li-ion cell's nominal is
	# 3.6 V against a LiPo's 3.7 V, so the same fully-charged 4.20 V/cell sits 0.4 V higher above
	# it at the pack. A real 4S Li-ion is labelled 14.4 V for exactly that reason.
	var full_lipo := _pack("LiPo").resting_voltage_v()
	var full_liion := _pack("Li-ion").resting_voltage_v()
	results.append(TestResult.new(
		"both chemistries reach 4.20 V per cell when full, from their own different nominals",
		is_equal_approx(full_lipo - 14.8, 4.0 * (4.20 - 3.70))
			and is_equal_approx(full_liion - 14.8, 4.0 * (4.20 - 3.60)),
		"LiPo %.2f V, Li-ion %.2f V, both from a 14.8 V nominal fixture" % [full_lipo, full_liion]
	))

	# An unrecognised chemistry must fall back to a curve rather than to a flat line or a crash,
	# and to a CONSISTENT pair — LiPo's curve against LiPo's nominal cell voltage, not one of
	# each. batteries.json is contributor-editable and a typo there must not silently delete the
	# model or bend it.
	var unknown := BatteryModel.create(14.8, 0.015, 1500.0, 4, "Unobtainium")
	var unknown_full := _at_soc(unknown, 1.0).resting_voltage_v()
	var unknown_empty := _at_soc(unknown, 0.0).resting_voltage_v()
	results.append(TestResult.new(
		"a chemistry nobody has heard of gets LiPo's curve AND LiPo's datum, not one of each",
		unknown_full == _pack("LiPo").resting_voltage_v() and unknown_empty < unknown_full - 3.0,
		"%.2f V full -> %.2f V empty, against LiPo's %.2f V full" % [
			unknown_full, unknown_empty, _pack("LiPo").resting_voltage_v()]
	))

	return results


# ---------------------------------------------------------------------------
# The fixed points, restated where the change could move them
# ---------------------------------------------------------------------------

## test_hover.gd and test_parts_system.gd already assert 11.7:1 and 29%. This asserts WHERE they
## are quoted, which is a different claim and the one the datum change could have broken: Build's
## analytic layer solves at nominal voltage, exactly, and no state of charge anywhere can reach it.
## A tolerance-based oracle check can absorb a small error here; this cannot.
static func _test_the_oracles_have_not_moved() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var nominal: float = float(build.battery["specs"]["nominal_v"])

	# THE DATUM, NAMED. Every figure on the stats panel is solved at this voltage and at no other.
	results.append(TestResult.new(
		"Build's analytic layer is solved at exactly the catalog's nominal voltage, the stated datum",
		build.resolve_open_circuit_v(Build.AT_NOMINAL) == nominal,
		"%.3f V, and the 11.7:1 and 29%% oracles are the figures at that voltage" % nominal
	))

	# ...and it stays there whatever the shelf says. Build must never read a pack's state of
	# charge: if it could, the reference build's quoted numbers would depend on how much flying
	# the person running the tests had done, and no two builders could compare anything.
	var quoted_hover := build.hover_throttle()
	var quoted_twr := build.thrust_to_weight()
	var drained := build.battery_model()
	drained.used_mah = drained.capacity_mah * 0.7
	results.append(TestResult.new(
		"a three-quarters-empty shelf does not move the quoted hover throttle or thrust-to-weight",
		build.hover_throttle() == quoted_hover and build.thrust_to_weight() == quoted_twr,
		"%.2f%% and %.2f:1, unchanged with a pack resting at %.2f V" % [
			quoted_hover * 100.0, quoted_twr, drained.resting_voltage_v()]
	))

	# The flying figure is a DIFFERENT number and is allowed to move — that is the whole point of
	# the split. On a fresh pack, which rests above nominal, it needs less throttle than the sheet.
	var fresh := build.hover_throttle_for(build.battery_model())
	results.append(TestResult.new(
		"the flying hover throttle on a fresh pack sits below the quoted nominal-datum figure",
		fresh < quoted_hover and fresh > 0.0,
		"%.1f%% flying on a full pack against %.1f%% quoted at nominal" % [
			fresh * 100.0, quoted_hover * 100.0]
	))

	return results
