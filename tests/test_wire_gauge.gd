class_name TestWireGauge
extends RefCounted
## The anchor of this suite is one number: 18 AWG silicone lead wire, computed at 17.55 g/m against
## the 17.86 g/m a wire vendor publishes for the same part.
##
## That test is the licence for every derived wire mass in the app, exactly as the 0.4 g standoff is
## for HardwareMass. If integrating copper and a silicone annulus did not land on a figure somebody
## else measured, then four motor leads' worth of derived mass would be four guesses stacked and the
## honest move would be to leave wire mass out of the model. It lands, so it stays — and the
## assertion is written against the PUBLISHED value with a 5% band, not against 17.55, because a
## test that compares the code to itself proves only that nobody edited the code today.

## 18 AWG UL 3239 silicone rubber lead wire, jacket OD 0.135": 12 lb per 1000 ft, off the vendor's
## own spec table. Converted here rather than pre-divided, so the external number is visible as the
## number they printed.
##     12 lb * 453.592 g/lb / (1000 ft * 0.3048 m/ft) = 17.858 g/m
## This is the external figure. Nothing in this repo derives it.
const PUBLISHED_18AWG_LB_PER_1000FT := 12.0
const G_PER_LB := 453.592
const M_PER_1000FT := 304.8
## HardwareMass's standoff check allows 5% against a vendor figure quoted to one significant figure.
## Same band here, and for a stronger reason: silicone compound density genuinely varies 1.1-1.4,
## and a band tighter than that spread would be a band tuned to one product.
const PUBLISHED_TOLERANCE := 0.05
## The second published figure about the same row, and the one that actually pins the area column.
## 18 AWG annealed copper is 20.9 milliohms per metre in every AWG table there is.
const PUBLISHED_18AWG_MOHM_PER_M := 20.9


static func run() -> Array:
	var results: Array = []

	results.append(_test_18awg_mass_matches_published())
	results.append(_test_resistance_scales_with_length_and_inverse_area())
	results.append(_test_resistance_matches_the_published_ohms_per_metre())
	results.append(_test_mass_scales_with_length_and_gauge())
	results.append(_test_table_is_monotonic_and_covers_the_range())
	results.append(_test_unknown_gauge_refuses_rather_than_interpolating())

	return results


## THE ANCHOR. §4.1, and the reason wire mass is derived rather than tabulated.
##
## TWO published figures about the SAME table row, in one check, and the pairing is deliberate.
## Mass is only weakly sensitive to the conductor area: widen the copper and the silicone annulus
## between the bundle and a fixed jacket OD shrinks by nearly as much, so a 9% area error moves mass
## by 3% and hides inside any band wide enough to allow for silicone density. Measured, not assumed
## — a mutation run put 0.823 mm2 at 0.900 and the mass half of this check went on passing.
##
## Resistance has no such cancellation: it is rho·L/A and nothing else. So the area column is held
## by the ohms-per-metre figure and the jacket geometry is held by the grams-per-metre figure, and
## between them every number in the 18 AWG row is pinned to something outside this repo.
static func _test_18awg_mass_matches_published() -> TestResult:
	var published := PUBLISHED_18AWG_LB_PER_1000FT * G_PER_LB / M_PER_1000FT
	var computed := WireGauge.mass_g(18, 1.0)
	var error := absf(computed - published) / published

	var passed := error <= PUBLISHED_TOLERANCE
	# And the magnitude has to be right for the reason the table exists at all: a metre of 18 AWG is
	# grams, not a rounding error, and four motor leads plus a trunk are the 14 g lump PW2 replaces.
	passed = passed and computed > 10.0 and computed < 30.0

	# The area column, held against the figure every AWG table there is prints for 18 AWG copper:
	# 20.9 milliohms per metre. 2% rather than 5% — this one has no compound-density spread in it.
	var computed_mohm := WireGauge.resistance_ohm(18, 1.0) * 1000.0
	var r_error := absf(computed_mohm - PUBLISHED_18AWG_MOHM_PER_M) / PUBLISHED_18AWG_MOHM_PER_M
	passed = passed and r_error <= 0.02

	return TestResult.new(
		"the 18 AWG row matches both published figures: %.2f g/m against 17.86, %.2f mohm/m against 20.9" % [computed, computed_mohm],
		passed,
		"mass %.2f vs %.2f g/m (12 lb/1000 ft), %.1f%% off (allowed %.0f%%); resistance %.2f vs %.1f mohm/m, %.1f%% off (allowed 2%%)" % [
			computed, published, error * 100.0, PUBLISHED_TOLERANCE * 100.0,
			computed_mohm, PUBLISHED_18AWG_MOHM_PER_M, r_error * 100.0]
	)


## R = rho·L/A, asserted as both of its terms separately, because a function that returned rho·L
## and ignored area would pass a length-only check and a function that returned rho/A would pass an
## area-only one.
static func _test_resistance_scales_with_length_and_inverse_area() -> TestResult:
	var short_run := WireGauge.resistance_ohm(18, 0.1)
	var long_run := WireGauge.resistance_ohm(18, 0.4)
	# Four times the length, four times the resistance. Not "more" — exactly four times.
	var length_ok := absf(long_run / short_run - 4.0) < 1e-6

	# And inversely with AREA, asserted as the exact area ratio off the table rather than as
	# "thinner is worse": 22 AWG is 0.326 mm2 against 18 AWG's 0.823, so the resistance ratio must be
	# 0.823/0.326 = 2.525. An implementation that MULTIPLIED by area instead of dividing would also
	# make a thinner wire differ — it would just differ the wrong way, and by that reciprocal.
	var awg22 := WireGauge.resistance_ohm(22, 1.0)
	var awg18 := WireGauge.resistance_ohm(18, 1.0)
	var expected_ratio: float = float(WireGauge.GAUGES[18][0]) / float(WireGauge.GAUGES[22][0])
	var area_ok := absf(awg22 / awg18 - expected_ratio) < 1e-6 and awg22 > awg18

	return TestResult.new(
		"resistance of a run scales with length and inversely with conductor area",
		length_ok and area_ok,
		"0.1 m %.5f ohm, 0.4 m %.5f ohm (ratio %.4f, want 4); 22 AWG/18 AWG %.4f, want %.4f" % [
			short_run, long_run, long_run / short_run, awg22 / awg18, expected_ratio]
	)


## The FAR end of the table, held against its own published figure: 12 AWG is 5.21 milliohms per
## metre. The anchor above pins 18 AWG; a single pinned row would leave a resistivity constant that
## is right and eight area entries that are only right relative to it. Two rows an octave apart
## cannot both be satisfied by a wrong constant.
static func _test_resistance_matches_the_published_ohms_per_metre() -> TestResult:
	var computed_12 := WireGauge.resistance_ohm(12, 1.0) * 1000.0
	var error_12 := absf(computed_12 - 5.21) / 5.21
	# And 24 AWG, at the thin end where the whoop harness lives: published 84.2 mohm/m.
	var computed_24 := WireGauge.resistance_ohm(24, 1.0) * 1000.0
	var error_24 := absf(computed_24 - 84.2) / 84.2

	var passed := error_12 < 0.02 and error_24 < 0.02
	return TestResult.new(
		"resistance per metre matches the published AWG table at both ends of the range",
		passed,
		"12 AWG %.2f mohm/m (published 5.21, %.1f%% off); 24 AWG %.2f mohm/m (published 84.2, %.1f%% off)" % [
			computed_12, error_12 * 100.0, computed_24, error_24 * 100.0]
	)


## Mass is linear in length — this is the term PW3's "halving lead length halves the drop" check has
## a mass counterpart to — and heavier per metre for thicker wire, monotonically.
static func _test_mass_scales_with_length_and_gauge() -> TestResult:
	var half := WireGauge.mass_g(18, 0.5)
	var whole := WireGauge.mass_g(18, 1.0)
	var linear := absf(whole - 2.0 * half) < 1e-9 and half > 0.0

	# 12 AWG is thicker copper AND a thicker jacket, so it must be several times heavier — asserted
	# as a factor rather than as ">" so that a mass function that had dropped the copper term and
	# kept only the jacket could not clear it.
	var awg12 := WireGauge.mass_g(12, 1.0)
	var heavier := awg12 > whole * 2.5

	return TestResult.new(
		"mass of a run is linear in length and rises with gauge",
		linear and heavier,
		"18 AWG 0.5 m %.2f g, 1.0 m %.2f g; 12 AWG 1.0 m %.2f g" % [half, whole, awg12]
	)


## The table itself: it covers what the catalog needs (12 down to 28) and every column moves the
## right way across it. A transposed digit in an area or an ampacity is the failure this catches,
## and it is the failure most likely to survive every other check in this file.
static func _test_table_is_monotonic_and_covers_the_range() -> TestResult:
	var gauges := WireGauge.gauges()
	var problems: Array[String] = []

	if gauges.front() != 12 or gauges.back() != 28:
		problems.append("range is %s..%s, want 12..28" % [gauges.front(), gauges.back()])

	# AWG counts DOWN as wire gets thicker, so ascending gauge number must mean falling area,
	# falling ampacity and falling mass per metre. All three, because a typo usually hits one.
	for i in range(1, gauges.size()):
		var thin: int = gauges[i]
		var thick: int = gauges[i - 1]
		if float(WireGauge.GAUGES[thin][0]) >= float(WireGauge.GAUGES[thick][0]):
			problems.append("%d AWG area is not below %d AWG's" % [thin, thick])
		if WireGauge.ampacity_a(thin) >= WireGauge.ampacity_a(thick):
			problems.append("%d AWG ampacity is not below %d AWG's" % [thin, thick])
		if WireGauge.mass_g(thin, 1.0) >= WireGauge.mass_g(thick, 1.0):
			problems.append("%d AWG mass/m is not below %d AWG's" % [thin, thick])
		# And the jacket must actually be a jacket: an OD authored at or under the conductor bundle
		# would clamp the annulus to zero and quietly ship a bare-copper mass.
		var area_mm2 := float(WireGauge.GAUGES[thin][0])
		var bundle_d: float = sqrt(4.0 * area_mm2 / WireGauge.STRAND_PACKING_FACTOR / PI)
		if float(WireGauge.GAUGES[thin][2]) <= bundle_d:
			problems.append("%d AWG jacket OD %.2f mm is inside its own %.2f mm bundle" % [
				thin, float(WireGauge.GAUGES[thin][2]), bundle_d])

	return TestResult.new(
		"the AWG table covers 12-28 and area, ampacity and mass per metre all fall as gauge rises",
		problems.is_empty(),
		"%d gauges checked, %s" % [gauges.size(),
			"no problems" if problems.is_empty() else "; ".join(problems)]
	)


## A 19 AWG lead is not a purchase. Interpolating one would put a number nobody published behind a
## voltage drop that reads as exact — so the table refuses, and ampacity refuses in the direction
## that WARNS rather than the direction that goes quiet.
static func _test_unknown_gauge_refuses_rather_than_interpolating() -> TestResult:
	var passed := WireGauge.resistance_ohm(19, 1.0) == 0.0
	passed = passed and WireGauge.mass_g(19, 1.0) == 0.0
	passed = passed and WireGauge.ampacity_a(19) == 0.0
	# Zero and negative lengths are a shorter wire, not an error — a builder dragging a length field
	# to nothing must not get a refusal.
	passed = passed and WireGauge.mass_g(18, 0.0) == 0.0 and WireGauge.resistance_ohm(18, -1.0) == 0.0
	# And the sane case must not be zero, or every clause above would pass on a stub.
	passed = passed and WireGauge.mass_g(18, 1.0) > 0.0 and WireGauge.ampacity_a(18) == 16.0

	return TestResult.new(
		"an off-table gauge returns nothing rather than an interpolated number, and 0 A reads as over-rating",
		passed,
		"19 AWG: R %.4f, m %.4f, I %.1f; 18 AWG: m %.2f g/m, I %.1f A" % [
			WireGauge.resistance_ohm(19, 1.0), WireGauge.mass_g(19, 1.0), WireGauge.ampacity_a(19),
			WireGauge.mass_g(18, 1.0), WireGauge.ampacity_a(18)]
	)
