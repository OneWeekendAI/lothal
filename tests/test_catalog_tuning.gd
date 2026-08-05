class_name TestCatalogTuning
extends RefCounted
## Does the derived tune actually FLY the same on every frame in the catalog?
##
## tests/test_rate_tune.gd checks the arithmetic. This one checks the claim, by flying twelve
## airframes spanning 4.9x of roll plant and 30x of yaw plant and asking whether they respond alike.
##
## ---------------------------------------------------------------------------
## WHY THE STEP IS SMALL, AND WHY THAT IS THE HONEST TEST
## ---------------------------------------------------------------------------
##
## tests/test_rate_step_response.gd grades the reference build on a 500 deg/s step, which is the
## right size for a step a pilot actually gives. It is the WRONG size for comparing airframes.
##
## A full-stick step is dominated by the SLEW FLOOR — the time the aircraft needs with its command
## pinned wide open, which no gain touches. On the 10" long-range's yaw axis that floor is 624 ms of
## a 722 ms settling time. Grading the tune there would be grading the airframe: two builds could
## have wildly different loops and near-identical numbers, and a tune that got twice as good would
## move the total by a tenth.
##
## So the comparison runs at 50 deg/s, where every aircraft in the catalog is inside its authority
## and the loop is the only thing being measured. That is not a softer test. It is the one the
## fixed gains fail catastrophically: yaw overshoot ran from 1.3% on the 10" to 64.6% on the whoop,
## against the reference build's 12.7% — a spread that the 500 deg/s step largely hides behind the
## slew floor, which is most of why nothing in the suite had ever noticed.
##
## The large-signal case is not abandoned. It is asserted at the bottom, in the only terms that mean
## anything there: no build may overshoot worse than the reference's own loop does.
##
## ---------------------------------------------------------------------------
## WHERE THE BAND COMES FROM
## ---------------------------------------------------------------------------
##
## From the reference build, measured at run time rather than typed in — the whole claim is
## "everything responds like the aircraft the gains were found on", so the reference IS the target
## and a literal here would be a second opinion about it.
##
## The widths are the residual the law leaves, plus a little. Every frame lands within 0.2% of the
## reference's overshoot and on the same millisecond of settling except the 10" long-range's yaw,
## which is the far end of a 30x plant spread and comes in 15% under on overshoot and 4% over on
## settling. So +/-20% and +/-10% are set by the worst real case rather than chosen to fit.
##
## A band wide enough to admit the CURRENT behaviour would be a test that cannot fail, which this
## project has been caught by before — so `_the_band_is_real` runs the whole comparison again on
## the fixed gains and requires it to FAIL. If someone widens the band far enough to be comfortable,
## that check goes red.

const DT := 0.001
const DURATION_S := 0.6
## Small enough that no frame in the catalog is slew-limited at it. The 10" long-range, the worst
## case by a distance, reaches 47.5 deg/s in 87 ms flat out against a 167 ms loop time constant.
const STEP_DEG_S := 50.0
const SETTLE_BAND_FRACTION := 0.05

const OVERSHOOT_TOLERANCE := 0.20
const SETTLE_TOLERANCE := 0.10
## The outer loop is not scaled at all — see angle_mode_controller.gd. This is that claim's band.
const OUTER_LOOP_TOLERANCE := 0.08

const WHOOP := "frame_65mm_whoop"
const LONG_RANGE := "frame_10in_long_range"


## Every frame in the catalog under ONE carried build, so the frame is the only thing that differs
## and any spread in the results is attributable to it. This is the same fixture labs-and-sim.md §7
## measured the 41x roll inertia on.
static func _frame_builds() -> Array:
	var catalog := PartsCatalog.load_default()
	var out: Array = []
	for frame in catalog.list_category("frame"):
		out.append(Build.from_ids(catalog, frame["part_id"], ReferenceBuild.MOTOR_ID,
			ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
			ReferenceBuild.FC_ID))
	return out


## One axis of one build, flown through the real DroneCore against the real gyro.
##
## `tune` null means the fixed gains — the behaviour before this slice, kept reachable so the band
## can be shown to discriminate rather than asserted to.
##
## The trace is ground TRUTH rather than the gyro reading, for test_rate_step_response.gd's reason:
## grading a loop with the signal it is closing on would hide any sensor error completely.
static func _step_response(build: Build, axis: int, tune: RateTune) -> Dictionary:
	var core := build.build_drone_core()
	core.powertrain.battery.set_to_nominal_datum()
	var controller := RateModeController.new()
	controller.adopt_tune(tune)

	var target := deg_to_rad(STEP_DEG_S)
	var throttle := build.hover_throttle()
	var setpoint := Vector3.ZERO
	setpoint[axis] = target / RateModeController.MAX_RATE_RAD_S

	var trace: Array = []
	for _i in int(DURATION_S / DT):
		core.step(controller.update(setpoint, core.gyro.rate_rad_s, throttle, DT), DT)
		trace.append(Gyro.contract_rates(core.rigid_body.angular_velocity_rad_s)[axis])

	var peak := target
	for v in trace:
		peak = maxf(peak, v)

	var settle_step := -1
	var band := target * SETTLE_BAND_FRACTION
	for i in range(trace.size() - 1, -1, -1):
		if absf(trace[i] - target) > band:
			settle_step = i + 1
			break

	return {
		"overshoot_pct": (peak - target) / target * 100.0,
		"settle_ms": 0.0 if settle_step == -1 else settle_step * DT * 1000.0,
	}


## The worst relative distance from the reference build's own response, over every frame and every
## axis, on the tune `derived` selects. Returns [worst_overshoot_ratio, worst_settle_ratio, label].
static func _worst_deviation(derived: bool) -> Array:
	var anchor: Array = []
	for axis in 3:
		anchor.append(_step_response(ReferenceBuild.build(), axis,
			RateTune.derive(ReferenceBuild.build()) if derived else null))

	var worst_over := 0.0
	var worst_settle := 0.0
	var label := ""
	for build in _frame_builds():
		var tune := RateTune.derive(build) if derived else null
		for axis in 3:
			var got := _step_response(build, axis, tune)
			var want: Dictionary = anchor[axis]
			var over_dev: float = absf(got.overshoot_pct - want.overshoot_pct) / want.overshoot_pct
			var settle_dev: float = absf(got.settle_ms - want.settle_ms) / want.settle_ms
			if maxf(over_dev / OVERSHOOT_TOLERANCE, settle_dev / SETTLE_TOLERANCE) \
					> maxf(worst_over / OVERSHOOT_TOLERANCE, worst_settle / SETTLE_TOLERANCE):
				label = "%s %s: overshoot %.2f%% vs %.2f%%, settle %.0f ms vs %.0f ms" % [
					build.frame["part_id"], RateTune.AXIS_NAMES[axis],
					got.overshoot_pct, want.overshoot_pct, got.settle_ms, want.settle_ms]
			worst_over = maxf(worst_over, over_dev)
			worst_settle = maxf(worst_settle, settle_dev)
	return [worst_over, worst_settle, label]


## Full stick, then hands off — the end-to-end claim rather than the numbers.
##
## Angle mode, through FlightController, so the outer loop is in the path too: a scaling law applied
## to the inner loop while the outer one stayed fixed would show up here as an aircraft that returns
## to level slowly, or oscillates about it, on the frames furthest from the reference.
static func _recovers_to_level(build: Build, tune: RateTune) -> Dictionary:
	var core := build.build_drone_core()
	var fc := FlightController.new()
	fc.rate_loop.adopt_tune(tune)
	var throttle := build.hover_throttle_for(core.powertrain.battery)
	core.prime_motors(throttle)

	var rc := {"roll": 1.0, "pitch": 0.0, "yaw": 0.0, "throttle": throttle}
	for _i in 400:
		core.step(fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT), DT)

	var banked := absf(core.rigid_body.orientation.get_euler(EULER_ORDER_YXZ).z)

	rc.roll = 0.0
	var worst_after_release := 0.0
	# How long the OUTER loop takes to bring the aircraft back inside a degree of level. This is
	# the figure that says whether AngleModeController's fixed LEVEL_P is safe: the outer loop
	# closes on the inner one rather than on the airframe, and the inner one's time constant is
	# what RateTune holds invariant, so this number should not depend on which frame is fitted.
	var level_ms := -1.0
	for i in 1200:
		core.step(fc.update(core.rigid_body.orientation, core.gyro.rate_rad_s, rc, DT), DT)
		var bank := absf(core.rigid_body.orientation.get_euler(EULER_ORDER_YXZ).z)
		if level_ms < 0.0 and bank < deg_to_rad(1.0):
			level_ms = (i + 1) * DT * 1000.0
		# Only the last third counts as "returned": the first two are the aircraft on its way back.
		if i > 800:
			worst_after_release = maxf(worst_after_release, bank)

	return {"banked_deg": rad_to_deg(banked), "residual_deg": rad_to_deg(worst_after_release),
		"level_ms": level_ms}


static func run() -> Array:
	var results: Array = []

	var after := _worst_deviation(true)
	results.append(TestResult.new(
		"every frame in the catalog responds like the reference build: overshoot within %.0f%%" % (OVERSHOOT_TOLERANCE * 100.0),
		after[0] < OVERSHOOT_TOLERANCE,
		"worst %.1f%% away — %s" % [after[0] * 100.0, after[2]]))
	results.append(TestResult.new(
		"every frame in the catalog responds like the reference build: settling within %.0f%%" % (SETTLE_TOLERANCE * 100.0),
		after[1] < SETTLE_TOLERANCE,
		"worst %.1f%% away — %s" % [after[1] * 100.0, after[2]]))

	# THE CHECK THAT KEEPS THE TWO ABOVE HONEST. The same comparison on the fixed gains has to come
	# out FAILING, or the band is wide enough to admit the behaviour this slice exists to replace
	# and neither of the assertions above is capable of going red.
	var before := _worst_deviation(false)
	results.append(TestResult.new(
		"and the band is real: the fixed gains do NOT satisfy it",
		before[0] > OVERSHOOT_TOLERANCE or before[1] > SETTLE_TOLERANCE,
		"fixed gains land %.0f%% out on overshoot and %.0f%% on settling — %s" % [
			before[0] * 100.0, before[1] * 100.0, before[2]]))

	# --- LARGE SIGNAL -----------------------------------------------------------------------
	#
	# A full-stick step is mostly slew floor, so settling time there is a statement about the
	# airframe. Overshoot is not: it is what the loop does on arrival, and no build may arrive
	# worse than the reference's loop does. The whoop failed this by seven times before.
	var catalog := PartsCatalog.load_default()
	var whoop := Build.from_ids(catalog, WHOOP, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)
	var long_range := Build.from_ids(catalog, LONG_RANGE, ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)

	# --- FLOWN ------------------------------------------------------------------------------
	var reference_flight := _recovers_to_level(ReferenceBuild.build(),
		RateTune.derive(ReferenceBuild.build()))
	for pair in [["65 mm whoop", whoop], ["10\" long-range", long_range]]:
		var name: String = pair[0]
		var build: Build = pair[1]
		var flown := _recovers_to_level(build, RateTune.derive(build))
		results.append(TestResult.new(
			"the %s banks on full stick and returns to level hands off" % name,
			flown.banked_deg > 20.0 and flown.residual_deg < 1.0,
			"banked %.1f deg, back to within %.2f deg" % [flown.banked_deg, flown.residual_deg]))

		# AngleModeController's LEVEL_P is NOT scaled, on the argument that the outer loop closes on
		# the inner one and the inner one's time constant is what RateTune holds invariant. This is
		# that argument's test. If the law ever stops equalising the inner loop, the outer loop's
		# recovery stops being comparable, and it shows up here before it shows up in the air.
		#
		# The band is 8%: the derived tune lands both extremes within 2% of the reference, and the
		# FIXED gains put the whoop 10% out and the 10" 24% out. So it is four times the worst real
		# case and still comfortably inside what it has to catch, rather than a width chosen to be
		# comfortable.
		var deviation: float = absf(flown.level_ms - reference_flight.level_ms) \
			/ reference_flight.level_ms
		results.append(TestResult.new(
			"the %s returns to level in the reference build's own time, on an UNSCALED outer loop" % name,
			flown.level_ms > 0.0 and deviation < OUTER_LOOP_TOLERANCE,
			"%.0f ms against the reference's %.0f ms (%.0f%% apart)" % [
				flown.level_ms, reference_flight.level_ms, deviation * 100.0]))

	return results
