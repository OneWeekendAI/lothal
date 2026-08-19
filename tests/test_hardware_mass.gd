class_name TestHardwareMass
extends RefCounted
## The anchor of this suite is one number: an M3 round aluminium standoff, D = 5 mm, bore = 3 mm,
## L = 12 mm, at 2700 kg/m³, computed at 0.407 g against the 0.4 g vendors list for the same part.
##
## That test is the licence for everything else in HardwareMass. If deriving fastener mass from
## geometry did not land on a real vendor's figure, then twenty screws' worth of derived mass would
## be twenty guesses stacked, and the honest move would be to leave hardware out of the model
## entirely. It lands, so it stays — and the assertion is written against the VENDOR value with a 5%
## band, not against 0.407, because a test that compares the code to itself proves only that nobody
## edited the code today.
##
## The three assemblability checks are each shown BOTH firing on a bad build AND silent on a good
## one. A check that fires on everything is not a check, and a warning function that returned a
## warning unconditionally would pass any test that only ever handed it a broken joint.

## Vendor listings put ten M3 5 mm x 12 mm aluminium standoffs at 4 g — 0.4 g each, quoted to one
## significant figure. This is the external number; it is not derived from anything in this repo.
const VENDOR_M3_STANDOFF_G := 0.4
## airframe.md §9 slice A6: "Standoff mass matches the vendor figure within 5%." Fixed by the
## design doc before the derivation was run, not chosen after seeing 0.407.
const VENDOR_TOLERANCE := 0.05


static func run() -> Array:
	var results: Array = []

	results.append(_test_m3_standoff_matches_vendor())
	results.append(_test_hex_standoff_uses_across_flats())
	results.append(_test_screw_thread_knockdown())
	results.append(_test_stack_height())
	results.append(_test_thread_engagement_fires_and_is_silent())
	results.append(_test_bottoming_out_fires_and_is_silent())
	results.append(_test_hole_to_edge_fires_and_is_silent())
	results.append(_test_hardware_is_worth_grams())

	return results


## THE ANCHOR. §5.1, and the reason hardware mass is computed rather than typed.
static func _test_m3_standoff_matches_vendor() -> TestResult:
	var computed := HardwareMass.standoff_round_mass_g(5.0, 3.0, 12.0, 2700.0)
	var error := absf(computed - VENDOR_M3_STANDOFF_G) / VENDOR_M3_STANDOFF_G

	# Two claims, both required: the closed form gives 0.407 g, and 0.407 g is within 5% of what a
	# vendor sells. The first without the second is arithmetic; the second is the physics.
	var passed := absf(computed - 0.407) < 0.001 and error <= VENDOR_TOLERANCE

	return TestResult.new(
		"M3 round aluminium standoff (D5/d3/L12, rho 2700) computes 0.407 g, within 5% of the 0.4 g vendors list",
		passed,
		"computed %.4f g vs vendor %.2f g — %.1f%% error (allowed %.0f%%)" % [
			computed, VENDOR_M3_STANDOFF_G, error * 100.0, VENDOR_TOLERANCE * 100.0]
	)


## A hex standoff of across-flats s is HEAVIER than a round one of diameter s, because the hexagon
## circumscribes that circle: (sqrt(3)/2)·s² = 0.866·s² against (pi/4)·s² = 0.785·s², a ratio of
## 1.103. Asserted as that exact ratio, so using the circumradius form — the classic slip, and a 15%
## error in the direction of an aircraft that weighs less than it does — fails here.
static func _test_hex_standoff_uses_across_flats() -> TestResult:
	var hex := HardwareMass.standoff_hex_mass_g(5.0, 3.0, 12.0, 2700.0)
	var round_same_d := HardwareMass.standoff_round_mass_g(5.0, 3.0, 12.0, 2700.0)

	# Bores are identical, so compare the solid areas, not the annuli.
	var bore_g := HardwareMass.standoff_round_mass_g(3.0, 0.0, 12.0, 2700.0)
	var ratio := (hex + bore_g) / (round_same_d + bore_g)
	var expected := (sqrt(3.0) / 2.0) / (PI / 4.0)

	var passed := absf(ratio - expected) < 0.002 and hex > round_same_d
	return TestResult.new(
		"hex standoff area is (sqrt(3)/2)·s² across the flats, not the circumradius form",
		passed,
		"hex %.4f g vs round %.4f g; solid-area ratio %.4f, expected %.4f" % [hex, round_same_d, ratio, expected]
	)


## The 15% thread knockdown of §5.1, isolated: a screw with a head of zero height must weigh
## 0.85² = 0.7225 of the plain cylinder of the same nominal diameter. Isolating it matters because
## the head term is the bigger number on a short screw and would hide a wrong shank.
static func _test_screw_thread_knockdown() -> TestResult:
	var threaded := HardwareMass.screw_mass_g(3.0, 10.0, 0.0, 0.0, 7850.0)
	var plain := HardwareMass.standoff_round_mass_g(3.0, 0.0, 10.0, 7850.0)
	var ratio := threaded / plain

	# And a whole M3x10 socket cap in steel, head 5.5 mm across and 3 mm tall, for the magnitude:
	# real M3x10 cap screws are ~1.0-1.1 g, and the model must land in that neighbourhood or the
	# 8-15 g hardware total the design doc quotes is meaningless.
	var whole := HardwareMass.screw_mass_g(3.0, 10.0, 5.5, 3.0, 7850.0)

	var passed := absf(ratio - 0.7225) < 0.001 and whole > 0.9 and whole < 1.3
	return TestResult.new(
		"screw shank takes the 0.85·d thread knockdown, and an M3x10 steel cap screw lands near 1 g",
		passed,
		"shank/plain ratio %.4f (want 0.7225); M3x10 cap screw %.3f g (want 0.9-1.3)" % [ratio, whole]
	)


## §5.2. The sum IS the vertical layout, so it is asserted on a build with different-length
## standoffs and unequal plates — equal values would pass under a mean, a max, or a count.
static func _test_stack_height() -> TestResult:
	var height := HardwareMass.stack_height_mm([20.0, 6.0], [2.0, 3.0])
	var passed := absf(height - 31.0) < 1e-6

	# Adding one more plate must move it by exactly that plate.
	var taller := HardwareMass.stack_height_mm([20.0, 6.0], [2.0, 3.0, 1.5])
	passed = passed and absf(taller - height - 1.5) < 1e-6

	return TestResult.new(
		"stack height is standoff lengths plus plate thicknesses, and each term moves it",
		passed,
		"20+6 standoff, 2+3 plate = %.2f mm (want 31.00); +1.5 mm plate = %.2f mm" % [height, taller]
	)


## Each of the next three: FIRES on the bad build, SILENT on the good one, and the good build is a
## genuinely marginal pass rather than a comfortable one, so a check with the inequality the wrong
## way round or a factor of two in the wrong place cannot clear both halves.
static func _test_thread_engagement_fires_and_is_silent() -> TestResult:
	# M3 through a 2 mm plate: an 8 mm screw leaves 6 mm of thread, fine. A 4.5 mm screw leaves
	# 2.5 mm, under the 3 mm one-diameter rule, and strips.
	var bad := HardwareMass.thread_engagement_warning(4.5, 3.0, 2.0)
	var good := HardwareMass.thread_engagement_warning(8.0, 3.0, 2.0)
	# Exactly 1×d — the boundary itself must PASS, since the rule is "at least".
	var boundary := HardwareMass.thread_engagement_warning(5.0, 3.0, 2.0)

	var passed := bad != null and good == null and boundary == null \
		and bad.id == &"thread_engagement" \
		and bad.severity == BuildWarning.Severity.IMPOSSIBLE \
		and absf(float(bad.values["engagement_mm"]) - 2.5) < 1e-6

	return TestResult.new(
		"thread engagement warns below 1x diameter and stays silent at or above it",
		passed,
		"4.5mm screw -> %s; 8mm -> %s; 5mm (exactly 3mm engagement) -> %s" % [
			_describe(bad), _describe(good), _describe(boundary)]
	)


static func _test_bottoming_out_fires_and_is_silent() -> TestResult:
	# 2 mm plate over a standoff bored 6 mm deep: 8 mm of hole. A 10 mm screw bottoms out with
	# 2 mm to spare and clamps nothing; an 8 mm screw is exactly right and must not warn.
	var bad := HardwareMass.bottoming_out_warning(10.0, 3.0, 2.0, 6.0)
	var good := HardwareMass.bottoming_out_warning(8.0, 3.0, 2.0, 6.0)

	var passed := bad != null and good == null \
		and bad.id == &"screw_bottoms_out" \
		and bad.severity == BuildWarning.Severity.IMPOSSIBLE \
		and absf(float(bad.values["overshoot_mm"]) - 2.0) < 1e-6

	return TestResult.new(
		"bottoming out warns when the screw is longer than plate plus bore, and not when it fits",
		passed,
		"10mm into 2+6mm -> %s; 8mm into 2+6mm -> %s" % [_describe(bad), _describe(good)]
	)


static func _test_hole_to_edge_fires_and_is_silent() -> TestResult:
	# M3: 4.5 mm of edge margin required. 3.0 mm tears out; 5.0 mm is fine; 4.5 mm is the boundary
	# and must pass.
	var bad := HardwareMass.hole_to_edge_warning(3.0, 3.0)
	var good := HardwareMass.hole_to_edge_warning(5.0, 3.0)
	var boundary := HardwareMass.hole_to_edge_warning(4.5, 3.0)

	var passed := bad != null and good == null and boundary == null \
		and bad.id == &"hole_to_edge" \
		and bad.severity == BuildWarning.Severity.LIMITING \
		and absf(float(bad.values["required_mm"]) - 4.5) < 1e-6

	return TestResult.new(
		"hole-to-edge warns inside 1.5x diameter and stays silent at or beyond it",
		passed,
		"3.0mm margin -> %s; 5.0mm -> %s; 4.5mm (exactly 1.5d) -> %s" % [
			_describe(bad), _describe(good), _describe(boundary)]
	)


## §5.1's closing claim, which is why any of this exists: the hardware on a 5" build is grams, not
## a rounding error — more than a camera, and currently invisible. Built from the material table
## rather than from constants, so a density typo in materials.json fails here too.
##
## The band is 8-30 g, WIDER than the 8-15 g §5.1 quotes, and the difference is stated rather than
## tuned away: this fixture is all-steel M3 hardware, and 24 M3x8 steel cap screws alone are 21 g.
## §5.1's 8-15 g must assume a lighter mix — M2 stack screws, aluminium or titanium motor screws,
## fewer of them — which is exactly the mix this function shows swinging the total by half. It is a
## MAGNITUDE check: hardware is worth grams and a builder can change how many.
static func _test_hardware_is_worth_grams() -> TestResult:
	var table := FrameMaterials.load_default()
	var alu := table.density("aluminium_6061")
	var steel := table.density("steel_fastener")

	# A representative 5": eight M3 aluminium standoffs (D5/d3, 6 x 20 mm bottom-to-top plate,
	# 2 x 6 mm stack) and twenty-four M3x8 steel cap screws.
	var total := 0.0
	for _i in range(6):
		total += HardwareMass.standoff_round_mass_g(5.0, 3.0, 20.0, alu)
	for _i in range(2):
		total += HardwareMass.standoff_round_mass_g(5.0, 3.0, 6.0, alu)
	for _i in range(24):
		total += HardwareMass.screw_mass_g(3.0, 8.0, 5.5, 3.0, steel)

	var passed := total > 8.0 and total < 30.0
	# And titanium screws must actually save weight — the reason titanium is a material choice here
	# and not a constant.
	var ti_total := 0.0
	for _i in range(24):
		ti_total += HardwareMass.screw_mass_g(3.0, 8.0, 5.5, 3.0, table.density("titanium_ti6al4v"))
	var steel_screws := total - (6 * HardwareMass.standoff_round_mass_g(5.0, 3.0, 20.0, alu) + 2 * HardwareMass.standoff_round_mass_g(5.0, 3.0, 6.0, alu))
	passed = passed and ti_total < steel_screws * 0.7

	return TestResult.new(
		"a 5-inch build's hardware is grams, not a rounding error, and titanium screws save most of it",
		passed,
		"8 standoffs + 24 M3x8 steel screws = %.1f g; the same screws in titanium %.1f g vs steel %.1f g" % [
			total, ti_total, steel_screws]
	)


static func _describe(warning: BuildWarning) -> String:
	if warning == null:
		return "silent"
	return "%s/%s" % [BuildWarning.severity_name(warning.severity), warning.id]
