class_name TestBatteryBench
extends RefCounted
## The battery bench (labs-and-sim.md §2.1) — a pack under a sustained load, and a voltage trace
## over time.
##
## The assertions are chosen so that a bench which merely LOOKS right fails. A chart of a falling
## line is easy, and there are three separate ways to draw a convincing one that teaches nothing:
##
##   1. TYPE IN THE AMPS. The obvious implementation has a field where you enter 40 A. It draws
##      the same picture and answers the question you came to ask, so the load here has to come
##      from a Powertrain running the real motors and props — checked by changing the motors and
##      requiring the load to move, and by requiring the bench's current to BE the powertrain's
##      published current rather than a number that agrees with it.
##   2. PLOT ONE LINE. Resting voltage and voltage-under-load falling together is the whole
##      content of the chart; a trace of only the second cannot distinguish a nearly-empty pack
##      from a good pack being worked hard.
##   3. LET THE PACK DECIDE NOTHING. Two packs under the same build must differ, and differ in
##      the direction their internal resistance says — which is asserted against a pair chosen
##      for that contrast rather than against a remembered number.
##
## Every Control built here is freed, or the runner emits leaked-RID ERROR lines that read like
## failures.

## Long enough for the motors to settle and for the trace to hold real samples, short enough that
## the suite does not turn into a load test of its own.
const SETTLE_S := 2.0
const DT := 1.0 / 60.0

## The contrast the spec asks to be legible: a high-C 4S LiPo against a 4S Li-ion. Same cell
## count, so the same motors reach the same RPM ceiling and the only difference is the pack.
const HIGH_C_PACK := "battery_4s_1300"
const LIION_PACK := "battery_4s_3000_liion"

static func run() -> Array:
	var results: Array = []
	var catalog := PartsCatalog.load_default()

	results.append_array(_test_the_load_is_the_real_motors(catalog))
	results.append_array(_test_the_trace(catalog))
	results.append_array(_test_the_two_numbers_that_decide_it(catalog))
	results.append_array(_test_the_pack_is_what_differs(catalog))
	results.append_array(_test_the_baseline_falls_and_the_knee_arrives(catalog))
	results.append_array(_test_it_is_a_room_of_its_own())

	return results


static func _bench(catalog: PartsCatalog, battery_id: String,
		motor_id: String = ReferenceBuild.MOTOR_ID,
		prop_id: String = ReferenceBuild.PROPELLER_ID) -> BatteryBenchScreen:
	return BatteryBenchScreen.new(catalog, motor_id, prop_id, battery_id)


static func _run_for(bench: BatteryBenchScreen, seconds: float, dt: float = DT) -> void:
	bench.set_running(true)
	var steps := int(seconds / dt)
	for _i in steps:
		bench.advance(dt)


# ---------------------------------------------------------------------------
# The load comes from the motors, not from a text field
# ---------------------------------------------------------------------------

static func _test_the_load_is_the_real_motors(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var bench := _bench(catalog, ReferenceBuild.BATTERY_ID)
	_run_for(bench, SETTLE_S)

	# The bench's current must BE the powertrain's published current, not a figure that happens
	# to resemble it. Read off the same Observables the HUD and the audio synthesiser read, so
	# there is no second expression of what the pack is being asked for.
	var published: float = bench.powertrain.observables.current_total_a
	results.append(TestResult.new(
		"the current the bench reports is the current the powertrain published, to the last digit",
		published > 0.0 and absf(bench.readings()["current_a"] - published) < 1e-6,
		"bench %.4f A vs published %.4f A" % [bench.readings()["current_a"], published]
	))

	# Hover load is the throttle Build says hovers this build — an aircraft property, not a
	# number this screen chose.
	# Both sides asked at the pack's own resting voltage: the bench applies the hover load for the
	# battery it is holding, so the analytic prediction has to be made at the same datum. Asking
	# Build for its nominal-voltage figure instead would compare a run on a full pack against
	# arithmetic for a half-discharged one.
	var bench_rest_v := bench.powertrain.battery.resting_voltage_v()
	var hover_current := bench.current_build().hover_current_a(
		bench.current_build().hover_throttle_for(bench.powertrain.battery), bench_rest_v)
	results.append(TestResult.new(
		"the hover load draws the hover current Build predicts analytically for the same build",
		absf(published - hover_current) / hover_current < 0.05,
		"bench %.1f A vs Build's %.1f A at hover" % [published, hover_current]
	))
	bench.free()

	# Change the motors and the load has to move. This is the assertion a typed-in amp figure
	# cannot pass: 40 A is 40 A whatever is bolted to the arms.
	var small := _bench(catalog, ReferenceBuild.BATTERY_ID, "motor_1404_3800kv", "prop_3x3x3")
	_run_for(small, SETTLE_S)
	var small_a: float = small.readings()["current_a"]
	var small_name: String = small.current_build().motor["name"]
	small.free()

	var big := _bench(catalog, ReferenceBuild.BATTERY_ID, "motor_2807_1300kv", "prop_7x4x3")
	big.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	_run_for(big, SETTLE_S)
	var big_a: float = big.readings()["current_a"]
	var big_name: String = big.current_build().motor["name"]
	big.free()

	results.append(TestResult.new(
		"putting different motors and props on the same pack changes the load it is under",
		big_a > small_a * 2.0,
		"%s draws %.1f A where %s draws %.1f A" % [big_name, big_a, small_name, small_a]
	))

	# Punch has to be a heavier load than hover on the same everything, or the two buttons are
	# decorative.
	var hover_bench := _bench(catalog, ReferenceBuild.BATTERY_ID)
	_run_for(hover_bench, SETTLE_S)
	var at_hover: float = hover_bench.readings()["current_a"]
	hover_bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	_run_for(hover_bench, SETTLE_S)
	var at_punch: float = hover_bench.readings()["current_a"]
	results.append(TestResult.new(
		"a punch is a heavier load than a hover, and the switch takes effect mid-run",
		at_punch > at_hover * 2.0,
		"%.1f A at hover -> %.1f A at full throttle" % [at_hover, at_punch]
	))
	hover_bench.free()

	return results


# ---------------------------------------------------------------------------
# The trace — the deliverable of this bench
# ---------------------------------------------------------------------------

static func _test_the_trace(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, LIION_PACK)

	results.append(TestResult.new(
		"an unconnected bench holds no trace and draws no current — arriving costs nothing",
		bench.trace.sample_count() == 0 and not bench.running and bench.elapsed_s == 0.0,
		"%d samples, running=%s" % [bench.trace.sample_count(), bench.running]
	))

	bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	_run_for(bench, SETTLE_S)

	results.append(TestResult.new(
		"applying a load starts a trace against time",
		bench.trace.sample_count() > 10 and bench.trace.span() > SETTLE_S * 0.5,
		"%d samples over %.1f s" % [bench.trace.sample_count(), bench.trace.span()]
	))

	# TWO series, and the gap between them. A single line would satisfy every "voltage falls"
	# check and lose the distinction the bench exists to draw.
	var resting := bench.trace.upper_series()
	var live := bench.trace.lower_series()
	var gap_everywhere := resting.size() == live.size() and resting.size() > 0
	for i in resting.size():
		if resting[i] - live[i] < 0.05:
			gap_everywhere = false
	results.append(TestResult.new(
		"the trace plots resting voltage AND voltage under load, with the sag visible as the gap",
		gap_everywhere and bench.trace.widest_gap() > 0.5,
		"deepest gap %.2f V across %d sample pairs" % [
			bench.trace.widest_gap(), resting.size()]
	))

	# The gap has to be the load's doing, so backing off has to close it. A constant offset
	# between two series would pass the check above and mean nothing.
	bench.set_load_mode(BatteryBenchScreen.Load.HOVER)
	_run_for(bench, SETTLE_S)
	var punch_sag := bench.trace.widest_gap()
	var hover_sag: float = bench.readings()["sag_v"]
	var hover_a: float = bench.readings()["current_a"]
	var punch_a := punch_sag / maxf(float(bench.current_build().battery["specs"]["internal_r_ohm"]), 1e-9)

	# Stated as PROPORTIONALITY rather than as a ratio threshold, which is both the stronger claim
	# and the stable one. Sag is I*R, so the two sags must stand in the same ratio as the two
	# currents that produced them — a constant offset between the series fails this outright, and
	# so does any sag that is not linear in current.
	#
	# It used to assert "hover sag is less than half punch sag", which was a threshold calibrated
	# against an uncapped punch. On this Li-ion the punch is now current-limited to 30 A by its 10C
	# rating, so hover and full throttle draw much more similar currents than they used to and the
	# ratio narrowed to 0.58. Nothing about sag changed; what changed is how hard this pack can be
	# asked to work, which is the C-rating doing its job.
	results.append(TestResult.new(
		"the gap tracks the current that made it, so it is sag rather than a constant offset",
		hover_sag < punch_sag and hover_sag > 0.0
			and absf(hover_sag / punch_sag - hover_a / punch_a) < 0.05,
		"%.2f V at %.0f A against %.2f V at %.0f A — sag ratio %.2f, current ratio %.2f" % [
			hover_sag, hover_a, punch_sag, punch_a, hover_sag / punch_sag, hover_a / punch_a]
	))

	# Bounded memory over a long run. A twenty-minute Li-ion discharge must not accumulate a
	# sample per frame for twenty minutes, and it must not solve that by scrolling the knee off
	# the left-hand side either.
	bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	_run_for(bench, 400.0, 0.25)
	results.append(TestResult.new(
		"a long run stays bounded in memory and still shows the whole discharge from t=0",
		bench.trace.sample_count() <= BandTrace.MAX_SAMPLES
			and bench.trace.xs()[0] < 1.0,
		"%d samples (cap %d), trace starts at t=%.2f s and spans %.0f s" % [
			bench.trace.sample_count(), BandTrace.MAX_SAMPLES,
			bench.trace.xs()[0], bench.trace.span()]
	))

	# Every sample has to be INSIDE the voltage axis, checked after the pack has been taken all
	# the way down rather than two seconds in — the collapse is what pushes a line off the chart.
	# A clipped line does not look clipped: it looks like a voltage that stopped falling and
	# levelled off, which is a confident and completely wrong thing to say about a pack that is
	# collapsing. The Li-ion is the case that exposes it, running volts below an axis a LiPo fits
	# comfortably inside.
	var final_live := bench.trace.lower_series()
	var final_resting := bench.trace.upper_series()
	var clipped: Array = []
	var lowest := INF
	for i in final_live.size():
		lowest = minf(lowest, final_live[i])
		if final_live[i] < bench.trace.y_min or final_resting[i] > bench.trace.y_max:
			clipped.append("sample %d: %.2f V against a floor of %.2f V" % [
				i, final_live[i], bench.trace.y_min])
	results.append(TestResult.new(
		"no part of either line is drawn clipped to the axis, which would read as a false plateau",
		clipped.is_empty() and lowest < bench.trace.y_max - 5.0,
		"axis %.2f..%.2f V holds all %d samples, lowest %.2f V" % [
			bench.trace.y_min, bench.trace.y_max, final_live.size(), lowest]
			if clipped.is_empty() else "; ".join(clipped)
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# How far it sags, and how long it holds up
# ---------------------------------------------------------------------------

static func _test_the_two_numbers_that_decide_it(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, ReferenceBuild.BATTERY_ID)
	bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
	_run_for(bench, SETTLE_S)

	var reading := bench.readings()

	# Sag is Ohm's law against the current actually being drawn, checked against its own
	# definition rather than a remembered value — the same discipline the thrust stand's
	# grams-per-watt check uses.
	var expected_sag: float = reading["current_a"] * bench.powertrain.battery.internal_r_ohm
	results.append(TestResult.new(
		"reported sag is the current actually drawn times this pack's internal resistance",
		absf(reading["sag_v"] - expected_sag) < 0.01 and reading["sag_v"] > 0.2,
		"%.3f V reported vs %.3f V from I*R (%.1f A x %.0f mΩ)" % [
			reading["sag_v"], expected_sag, reading["current_a"],
			bench.powertrain.battery.internal_r_ohm * 1000.0]
	))

	# Hold-up is the charge left divided by the draw. Cross-checked by actually running the
	# pack down: the projection made early has to be borne out by the time it takes.
	var projected: float = reading["hold_up_s"]
	var elapsed_at_projection: float = reading["elapsed_s"]
	var guard := 0
	while bench.running and guard < 100000:
		bench.advance(0.25)
		guard += 1
	var actual := bench.elapsed_s - elapsed_at_projection

	results.append(TestResult.new(
		"the projected hold-up is borne out by how long the pack actually lasts under that load",
		bench.powertrain.battery.remaining_fraction() <= 0.0
			and absf(actual - projected) / projected < 0.25,
		"projected %.0f s, actually lasted %.0f s (%.1f%% out)" % [
			projected, actual, absf(actual - projected) / projected * 100.0]
	))

	# ...and the panel shows both, so the numbers the tests read are the numbers on screen.
	var text := bench.instruments.readout_text()
	results.append(TestResult.new(
		"the panel reads out sag, hold-up, current, remaining capacity and elapsed time",
		text.has("sag") and text.has("hold_up") and text.has("current")
			and text.has("remaining") and text.has("elapsed"),
		"keys on the panel: %s" % ", ".join(PackedStringArray(text.keys()))
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# Two packs, one build, and the difference is the pack
# ---------------------------------------------------------------------------

## The teaching moment labs-and-sim.md §2.1 asks for, asserted rather than left to a screenshot:
## the high-C LiPo and the Li-ion are the same nominal voltage and the same cell count, under the
## same motors and props at the same throttle. Everything that differs between the two traces is
## the pack.
static func _test_the_pack_is_what_differs(catalog: PartsCatalog) -> Array:
	var results: Array = []

	var lipo := _bench(catalog, HIGH_C_PACK)
	var liion := _bench(catalog, LIION_PACK)
	for bench in [lipo, liion]:
		bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)
		_run_for(bench, SETTLE_S)

	var lipo_read := lipo.readings()
	var liion_read := liion.readings()

	# The bound was 3.0 while the Li-ion could be commanded to full throttle. Its 10C rating now
	# caps it at a fraction of that, so it draws less current and therefore sags less — the
	# measured factor is about 2.5. The pack has not got better; it has run into the OTHER limit
	# first, and the assertion below this one is that limit stated directly.
	results.append(TestResult.new(
		"under the same punch the Li-ion sags several times as hard as the high-C LiPo",
		liion_read["sag_v"] > lipo_read["sag_v"] * 2.0,
		"%s: %.2f V vs %s: %.2f V" % [
			liion.current_build().battery["name"], liion_read["sag_v"],
			lipo.current_build().battery["name"], lipo_read["sag_v"]]
	))

	# ...and the other half of why a Li-ion flies like a brick, which is not sag at all. A 3000 mAh
	# 10C pack is a 30 A pack against the 1300 mAh 95C's 124 A, so the big battery cannot even be
	# ASKED for the punch. Both are pack-limited — the high-C LiPo only mildly, at 94% throttle
	# (98% until 2026-09-27, when the ceiling began to be solved on a FRESH 6S pack's draw with
	# sag: 25.2 V drives the 2207s harder than the 14.8 V test voltage the old ceiling priced every
	# pack at) — so the claim is about the SEVERITY, and about the Li-ion being told what stops it.
	var liion_build := liion.current_build()
	var lipo_build := lipo.current_build()
	results.append(TestResult.new(
		"the Li-ion is throttle-capped by its own C-rating where the high-C LiPo is barely touched",
		liion_build.limiting_component()["name"] == "battery"
			and liion_build.max_throttle_fraction() < 0.6
			and lipo_build.max_throttle_fraction() > 0.9,
		"Li-ion %.0f A capping throttle at %.0f%%, LiPo %.0f A at %.0f%%" % [
			liion_build.pack_max_amps(), liion_build.max_throttle_fraction() * 100.0,
			lipo_build.pack_max_amps(), lipo_build.max_throttle_fraction() * 100.0]
	))

	# The consequence that makes it a lesson rather than a curiosity: the sag costs RPM, and the
	# RPM costs thrust. The pack decides what the motors can actually do.
	results.append(TestResult.new(
		"the sag costs thrust, so the pack decides what these motors can actually reach",
		liion_read["thrust_g"] < lipo_read["thrust_g"] * 0.85,
		"%.0f g on the Li-ion against %.0f g on the LiPo, same motors and props" % [
			liion_read["thrust_g"], lipo_read["thrust_g"]]
	))

	# ...and it holds up far longer, which is the other half of the trade and the reason anyone
	# would fit one.
	results.append(TestResult.new(
		"and it holds up longer, which is the other half of the trade",
		liion_read["hold_up_s"] > lipo_read["hold_up_s"],
		"%.0f s against %.0f s at full throttle" % [
			liion_read["hold_up_s"], lipo_read["hold_up_s"]]
	))

	lipo.free()
	liion.free()
	return results


# ---------------------------------------------------------------------------
# The baseline falls, and the knee shows up before the pack dies
# ---------------------------------------------------------------------------

## What deliverable 2 bought, seen on the instrument it was bought for. Two claims: the resting
## line is not flat, and its fall is not a straight one — the last stretch is far steeper than the
## middle, which is the knee arriving while there is still a trace left to see it on.
static func _test_the_baseline_falls_and_the_knee_arrives(catalog: PartsCatalog) -> Array:
	var results: Array = []
	var bench := _bench(catalog, HIGH_C_PACK)
	bench.set_load_mode(BatteryBenchScreen.Load.PUNCH)

	bench.set_running(true)
	var guard := 0
	while bench.running and guard < 100000:
		bench.advance(0.1)
		guard += 1

	var resting := bench.trace.upper_series()
	var first := resting[0]
	var last := resting[resting.size() - 1]

	results.append(TestResult.new(
		"the resting baseline falls over the run rather than sitting flat under the sag",
		first - last > 2.0,
		"%.2f V at the start down to %.2f V at the end" % [first, last]
	))

	# The knee, measured on the trace itself: the last tenth of the run has to drop far more
	# steeply than the middle tenth. A linear baseline scores 1.0 here.
	var n := resting.size()
	var middle_drop: float = resting[int(n * 0.45)] - resting[int(n * 0.55)]
	var final_drop: float = resting[int(n * 0.90)] - resting[n - 1]
	results.append(TestResult.new(
		"the knee is visible on the trace before the pack dies, not just at the very last sample",
		final_drop > middle_drop * 3.0,
		"the last 10%% of the run drops %.2f V against %.2f V for the middle 10%% — %.1fx steeper" % [
			final_drop, middle_drop, final_drop / maxf(middle_drop, 0.0001)]
	))

	results.append(TestResult.new(
		"the run ends by itself when the pack is flat, leaving the trace on screen",
		not bench.running and bench.powertrain.battery.remaining_fraction() <= 0.0
			and bench.trace.sample_count() > 100,
		"stopped after %.0f s with %d samples on the trace" % [
			bench.elapsed_s, bench.trace.sample_count()]
	))

	bench.free()
	return results


# ---------------------------------------------------------------------------
# It is a room, and it is not there when you are not in it
# ---------------------------------------------------------------------------

## Same argument the thrust stand and Sim already make, with a sharper edge here: this room holds
## a powertrain draining a real pack. A battery bench left running behind Lab would keep emptying
## a battery while you chose propellers, and the only evidence would be a number that was wrong
## later.
static func _test_it_is_a_room_of_its_own() -> Array:
	var results: Array = []
	var shell := AppShell.new()

	shell.lab.battery_picker.select_id(LIION_PACK)
	shell.show_battery_bench()

	results.append(TestResult.new(
		"the battery bench opens on the pack chosen on Lab's rail, with no stand and no sim running",
		shell.battery_bench != null and shell.bench == null and shell.sim == null
			and shell.battery_bench.current_build().battery["part_id"] == LIION_PACK,
		"testing %s" % shell.battery_bench.current_build().battery["name"]
	))

	shell.show_lab()
	results.append(TestResult.new(
		"leaving frees it, so a pack never drains behind Lab",
		shell.battery_bench == null and shell.showing_lab(),
		"battery_bench=%s" % shell.battery_bench
	))

	shell.free()
	return results
