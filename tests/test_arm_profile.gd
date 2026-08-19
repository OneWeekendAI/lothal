class_name TestArmProfile
extends RefCounted
## Measuring an arm's width profile off its own outline — airframe.md §10 question 1.
##
## ## Why this suite exists at all
##
## Up to now every beam number in the app came from `frames.json`'s `arm_width_mm`, which exists on
## exactly ONE of fifteen frames because no vendor publishes it (§9a). That is fine for a catalog
## and useless for an editor: a frame you draw yourself has no catalog entry, and the whole point of
## drawing one is that its arms are whatever you made them. So the width has to come from the
## polygon, and `ArmProfile` is the one place it does.
##
## §10 q1 settled that the CENTRELINE is authored and the WIDTH is measured. This suite is the
## measurement half. It asserts against shapes whose answer is known by construction — a rectangle
## is its own width everywhere, a trapezoid is linear between its ends — so a failure is a bug in
## the measurement and never a disagreement about what the right answer was.
##
## ## MUTATION NOTES
##
## The two that matter:
##
##   - `_test_rotation_does_not_move_the_widths` fails the moment anyone measures width along the
##     global Y axis instead of perpendicular to the authored centreline. Every arm in a generated
##     preset lies on a 45 degree diagonal, so that bug would be invisible on the shapes a lazier
##     suite would use and wrong on every real frame.
##   - `_test_a_notch_narrows_the_arm_where_it_bites` fails if the measurement takes the outer
##     extent of all crossings rather than the span containing the centreline. That version passes
##     on every convex shape and silently reports a notched arm as full width at its weakest
##     station.

const EPS := 1.0e-9


static func run() -> Array:
	var results: Array = []
	results.append(_test_a_rectangle_is_its_own_width_everywhere())
	results.append(_test_a_trapezoid_is_linear_between_its_ends())
	results.append(_test_rotation_does_not_move_the_widths())
	results.append(_test_the_ends_are_measured_not_dropped())
	results.append(_test_a_notch_narrows_the_arm_where_it_bites())
	results.append(_test_a_centreline_outside_the_outline_is_refused())
	results.append(_test_a_zero_length_centreline_is_refused())
	results.append(_test_a_measured_rectangle_beam_equals_the_uniform_one())
	return results


# ---------------------------------------------------------------------------
# Shapes whose answer is known by construction
# ---------------------------------------------------------------------------

## A rectangle spanning x = 0..L at half-width h. Its width is 2h at every station, exactly.
static func _rectangle(length: float, half_width: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -half_width),
		Vector2(length, -half_width),
		Vector2(length, half_width),
		Vector2(0.0, half_width),
	])


## A symmetric taper: half-width h0 at the root, h1 at the tip, straight between.
static func _trapezoid(length: float, h0: float, h1: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0.0, -h0),
		Vector2(length, -h1),
		Vector2(length, h1),
		Vector2(0.0, h0),
	])


## Rotation done in DOUBLES, on the flat representation a document actually stores.
##
## Rotating a `PackedVector2Array` instead would be the obvious way to write this and would make the
## test lie: `Vector2` is 32-bit, so the fixture itself would arrive carrying ~1e-5 mm of noise, and
## the assertion below would have to be loosened to about 1e-4 mm to accommodate a defect in the
## TEST. At that tolerance a genuinely wrong perpendicular on a nearly-square arm would pass. The
## measurement under test reads doubles, so the fixture hands it doubles.
static func _rotated_flat(points: PackedVector2Array, degrees: float) -> PackedFloat64Array:
	var angle := deg_to_rad(degrees)
	var c := cos(angle)
	var sn := sin(angle)
	var out := PackedFloat64Array()
	for p in points:
		out.append(float(p.x) * c - float(p.y) * sn)
		out.append(float(p.x) * sn + float(p.y) * c)
	return out


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

## MUTATION: return the polygon's bounding-box height instead of the perpendicular span and this
## still passes — which is why the trapezoid and the notch tests below exist. This one only pins
## the easy case, so that a failure here means the machinery is broken rather than subtle.
static func _test_a_rectangle_is_its_own_width_everywhere() -> TestResult:
	var profile := ArmProfile.measure(_rectangle(100.0, 6.0), Vector2.ZERO, Vector2(100.0, 0.0))
	var ok: bool = profile["errors"].is_empty()
	var worst := 0.0
	for w in profile["widths_mm"]:
		worst = maxf(worst, absf(w - 12.0))
	return TestResult.new(
		"A rectangular arm measures 12 mm wide at every station",
		ok and worst < EPS,
		"worst deviation %.10f mm over %d stations" % [worst, profile["widths_mm"].size()])


## The taper is the number §4.2's compliance integral is most sensitive to, and a linear taper has
## an exact midpoint. MUTATION: sample the outline at the root only (the "arms are uniform" shortcut
## the catalog forced on us) and the midpoint reads 20 instead of 15.
static func _test_a_trapezoid_is_linear_between_its_ends() -> TestResult:
	var profile := ArmProfile.measure(_trapezoid(100.0, 10.0, 5.0), Vector2.ZERO, Vector2(100.0, 0.0))
	var stations: PackedFloat64Array = profile["stations_mm"]
	var widths: PackedFloat64Array = profile["widths_mm"]
	var worst := 0.0
	for i in range(stations.size()):
		# Half-widths 10 -> 5 means widths 20 -> 10, straight: w(s) = 20 - 0.1*s.
		worst = maxf(worst, absf(widths[i] - (20.0 - 0.1 * stations[i])))
	return TestResult.new(
		"A tapered arm measures its taper, not its root",
		profile["errors"].is_empty() and worst < 1.0e-6,
		"worst deviation %.10f mm from the exact taper" % worst)


## Every arm in a generated preset lies on a diagonal, so measuring along a global axis is a bug
## that hides on textbook shapes and corrupts every real frame.
##
## MUTATION: replace the perpendicular with Vector2.UP and this fails by a factor of ~1.41 on the
## 45 degree case.
static func _test_rotation_does_not_move_the_widths() -> TestResult:
	var flat := ArmProfile.measure(_trapezoid(100.0, 10.0, 5.0), Vector2.ZERO, Vector2(100.0, 0.0))
	var worst := 0.0
	for degrees in [30.0, 45.0, 135.0, -60.0]:
		var angle := deg_to_rad(degrees)
		var turned := ArmProfile.measure_flat(
			_rotated_flat(_trapezoid(100.0, 10.0, 5.0), degrees),
			0.0, 0.0,
			100.0 * cos(angle), 100.0 * sin(angle))
		if not turned["errors"].is_empty():
			return TestResult.new(
				"An arm's width is measured perpendicular to its own centreline",
				false, "rotation by %.0f deg produced %s" % [degrees, turned["errors"]])
		for i in range(flat["widths_mm"].size()):
			worst = maxf(worst, absf(turned["widths_mm"][i] - flat["widths_mm"][i]))
	return TestResult.new(
		"An arm's width is measured perpendicular to its own centreline",
		worst < 1.0e-9,
		"worst deviation %.10f mm across four rotations" % worst)


## The root station is where the bending moment is largest (§4.5) and the tip station is where the
## motor bolts on. Both sit exactly on a polygon edge, which is precisely where a naive
## straddle test drops the crossing and reports zero width.
##
## MUTATION: use a strict `da < 0 < db` straddle test and the tip station reads 0, which then makes
## ArmBeam refuse the arm entirely — an arm you drew correctly, refused for a rounding reason.
static func _test_the_ends_are_measured_not_dropped() -> TestResult:
	var profile := ArmProfile.measure(_rectangle(100.0, 6.0), Vector2.ZERO, Vector2(100.0, 0.0))
	var widths: PackedFloat64Array = profile["widths_mm"]
	var first := widths[0]
	var last := widths[widths.size() - 1]
	return TestResult.new(
		"The root and tip stations are measured, not dropped off the ends",
		absf(first - 12.0) < EPS and absf(last - 12.0) < EPS,
		"root %.6f mm, tip %.6f mm" % [first, last])


## A lightening cutout is a real thing a builder can draw, and an arm with one is not the same arm
## as one with the same outer extent. The measurement must span the MATERIAL the centreline actually
## runs through.
##
## MUTATION: take min/max of all crossings instead of the interval containing zero, and the notched
## station reports the full 12 mm — a notched arm reported as solid, at the exact station where it
## is weakest.
static func _test_a_notch_narrows_the_arm_where_it_bites() -> TestResult:
	# A rectangle with a slot cut in from the +y side at midspan, stopping 2 mm short of the
	# centreline. The material the centreline runs through is then y = -6..+2, i.e. 8 mm.
	var outline := PackedVector2Array([
		Vector2(0.0, -6.0), Vector2(100.0, -6.0), Vector2(100.0, 6.0),
		Vector2(55.0, 6.0), Vector2(55.0, 2.0), Vector2(45.0, 2.0), Vector2(45.0, 6.0),
		Vector2(0.0, 6.0),
	])
	var profile := ArmProfile.measure(outline, Vector2.ZERO, Vector2(100.0, 0.0), 21)
	var stations: PackedFloat64Array = profile["stations_mm"]
	var widths: PackedFloat64Array = profile["widths_mm"]
	var notched := -1.0
	var clear := -1.0
	for i in range(stations.size()):
		if absf(stations[i] - 50.0) < EPS:
			notched = widths[i]
		if absf(stations[i] - 10.0) < EPS:
			clear = widths[i]
	return TestResult.new(
		"A notch narrows the arm at the station it bites",
		absf(notched - 8.0) < 1.0e-6 and absf(clear - 12.0) < 1.0e-6,
		"notched station %.3f mm, clear station %.3f mm" % [notched, clear])


## An arm whose centreline misses its own plate is an authoring mistake, and the honest answer is
## "I cannot measure this", never a plausible width. §0's rule: nothing on screen may come from a
## number the physics did not read.
static func _test_a_centreline_outside_the_outline_is_refused() -> TestResult:
	var profile := ArmProfile.measure(
		_rectangle(100.0, 6.0), Vector2(0.0, 40.0), Vector2(100.0, 40.0))
	return TestResult.new(
		"A centreline that misses the plate is refused, not guessed",
		not profile["errors"].is_empty() and profile["widths_mm"].is_empty(),
		"errors: %s" % [profile["errors"]])


static func _test_a_zero_length_centreline_is_refused() -> TestResult:
	var profile := ArmProfile.measure(_rectangle(100.0, 6.0), Vector2.ZERO, Vector2.ZERO)
	return TestResult.new(
		"A zero-length centreline is refused",
		not profile["errors"].is_empty(),
		"errors: %s" % [profile["errors"]])


## The bridge to the physics: a measured rectangle must produce the SAME beam as the hand-built
## uniform one it is a picture of. If these two ever disagree, the app has two arm models again,
## which is the exact divergence airframe_model.gd was created to end.
##
## MUTATION: emit stations in millimetres rather than metres into ArmBeam and the stiffness is out
## by 10^3 — a number that still looks like a number.
static func _test_a_measured_rectangle_beam_equals_the_uniform_one() -> TestResult:
	var materials := FrameMaterials.load_default()
	var measured := ArmProfile.beam(
		_rectangle(100.0, 6.0), Vector2.ZERO, Vector2(100.0, 0.0),
		5.0, "carbon_3k_twill_0_90", materials)
	var uniform := ArmBeam.uniform(
		0.100, 0.012, 0.005, "carbon_3k_twill_0_90", materials)
	if measured == null:
		return TestResult.new(
			"A measured rectangle produces the same beam as the uniform one",
			false, "measurement returned null")
	var k_measured := measured.k_tip_n_per_m()
	var k_uniform := uniform.k_tip_n_per_m()
	var relative := absf(k_measured - k_uniform) / k_uniform
	return TestResult.new(
		"A measured rectangle produces the same beam as the uniform one",
		relative < 1.0e-9,
		"measured %.4f N/m, uniform %.4f N/m, relative %.10f" % [k_measured, k_uniform, relative])
