class_name TestForwardFlight
extends RefCounted
## The forward-flight propeller model (docs/lothal/plans/2026-08-14-forward-flight-prop-design.md),
## as it stands after P6's closure: the model UNDER these checks is now blade-element theory on the
## blade's own planform, read through `BemtRatios`, and `PropellerModel::thrust_factor` /
## `power_factor` are deleted. Not one check here changed its CLAIM in that swap — the claims were
## always about the physics rather than about the implementation — but every one of them now
## exercises BEMT, so this file is the regression net the closure was carried out under.
##
## Every check here was DEMONSTRATED TO FAIL before it was kept — the way each one was made to fail
## is written above it, so a future reader can break it again in ten seconds rather than trusting
## that someone once did. A test that passes with and without its fix is worse than no test, and
## this repository has shipped one before.
##
## THE CHECK THAT MATTERS IS THE FIRST ONE. There are two aerodynamic effects here with opposite
## signs: axial inflow unloads the prop (thrust down, so throttle up, so current up), and edgewise
## flow makes the rotor cheaper (current down). A model with only the first is not a partial
## improvement, it is a regression wearing a physics costume — forward flight would cost MORE than
## hovering and every flight-time figure in the app would get shorter. Nothing in the suite before
## this file flew forward and looked at current, so it would have shipped in silence.
##
## Nothing here may quote an error bar. The model is characteristic, not predictive (validation.md
## §9's rule): no manufacturer publishes C_T(J) for an FPV propeller, so every figure asserted below
## is the model agreeing with itself about a mechanism, never a measurement.

## The three fixed points, to the digit. Hover and static, i.e. J = 0 — a correct implementation
## leaves them BIT-IDENTICAL, not merely close, because the forward-flight terms short-circuit at
## zero velocity rather than evaluating to something that rounds to one.
const REFERENCE_AUW_G := 507.5
const REFERENCE_TWR := 11.43
const REFERENCE_HOVER_THROTTLE := 0.299

const CRUISE_MPS := 10.0


static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()

	results.append(_translational_lift_is_not_missing(build))
	results.append_array(_the_three_oracles_have_not_moved(build))
	results.append(_the_static_callers_are_still_static(build))
	results.append_array(_thrust_falls_with_airspeed(build))
	results.append(_the_power_curve_has_a_minimum(build))
	results.append(_descent_is_declined_rather_than_guessed(build))
	results.append(_a_bench_is_the_static_path(build))
	results.append_array(_flight_time_comes_from_the_profile(build))
	results.append(_top_speed_is_unchanged_for_the_reference_build(build))
	results.append(_the_unloading_cap_binds_on_a_build_that_needs_it())
	results.append_array(_the_builder_is_told_when_the_prop_is_the_limit(build))

	return results


# ---------------------------------------------------------------------------
# The trap
# ---------------------------------------------------------------------------

## TO MAKE THIS FAIL: return 1.0 unconditionally from `BemtRatios::power_ratio` — that is precisely
## a model with effect (a) and not effect (b), since the trim would still raise the throttle to hold
## the aircraft up while the rotor doing that work never got cheaper. Under BEMT the reference build
## draws 10.15 A at 10 m/s against 10.95 A hovering, 93%; with the power ratio pinned at 1 the
## throttle rise is all that survives and the figure goes above the hover current.
##
## Both models raise the throttle to trim, because both unload the prop. Only the full one knows
## the rotor doing that work has become cheaper.
static func _translational_lift_is_not_missing(build: Build) -> TestResult:
	var hover_a := build.hover_current_a(build.hover_throttle())
	var ceiling: float = build.peak_thrust()["throttle"]
	var cruise_a := build.flight_current_at_a(CRUISE_MPS, 1.0, ceiling)
	return TestResult.new(
		"flying forward at a moderate speed costs LESS current than hovering",
		cruise_a < hover_a,
		"%.1f m/s draws %.2f A against %.2f A hovering (%.0f%%)" % [
			CRUISE_MPS, cruise_a, hover_a, cruise_a / hover_a * 100.0]
	)


# ---------------------------------------------------------------------------
# The invariants
# ---------------------------------------------------------------------------

## TO MAKE THESE FAIL: route max_total_thrust_n() through the in-flight form at any non-zero
## airspeed. Sixteen checks across nine files go red, TWR reads 11.47, and the whole project says
## so at once — which is the coupling worth having.
##
## Worth stating what does NOT break them, because it was the first guess and it was wrong:
## deleting the zero-velocity short circuit in the forward-flight ratio changes nothing here. These three
## figures never touch the forward-flight code at all — they are the static path, and what protects
## them is that the static path stayed static. That is the next check, and these two are a pair.
static func _the_three_oracles_have_not_moved(build: Build) -> Array:
	return [
		TestResult.new("the reference build still weighs exactly 507.5 g",
			is_equal_approx(snappedf(build.all_up_weight_g(), 0.1), REFERENCE_AUW_G),
			"%.4f g" % build.all_up_weight_g()),
		TestResult.new("thrust-to-weight is still exactly 11.43:1",
			is_equal_approx(snappedf(build.thrust_to_weight(), 0.01), REFERENCE_TWR),
			"%.6f:1" % build.thrust_to_weight()),
		TestResult.new("hover throttle is still exactly 29.9%",
			is_equal_approx(snappedf(build.hover_throttle(), 0.001), REFERENCE_HOVER_THROTTLE),
			"%.6f%%" % (build.hover_throttle() * 100.0)),
	]


## The callers that legitimately want a stand rather than an aircraft must keep getting one.
##
## TO MAKE THIS FAIL: multiply max_total_thrust_n() by `BemtRatios::thrust_ratio` at any non-zero
## airspeed. The bench figure drops, and with it the 11.69:1 above and every held-out
## point ThrustValidation checks its 10%/20% tiers against.
## The ratio must be EXACTLY 1.0 at rest — the bit, not a rounding — because the whole calibration
## chain P5 anchored hangs off the static solve. Under a tabulated surface (P6's closure) that is a
## sharper claim than it was: a bilinear read of node (0,0) has to return the node's own value with
## no arithmetic done to it, and `BemtRatios::read`'s zero-velocity short circuit is what guarantees
## it rather than the interpolation happening to land there.
static func _the_static_callers_are_still_static(build: Build) -> TestResult:
	var rpm := build.max_rpm_at_nominal()
	var static_n := PropellerModel.thrust_n(build.k_t, rpm)
	var ratio_at_rest := build.forward_ratios().thrust_ratio(rpm, 0.0, 0.0)
	return TestResult.new(
		"the forward-flight ratio is EXACTLY 1.0 when the aircraft is not moving",
		ratio_at_rest == 1.0 and is_equal_approx(build.max_total_thrust_n(), 4.0 * static_n),
		"ratio at rest %.20f, bench figure %.9f N (4x static = %.9f N)" % [
			ratio_at_rest, build.max_total_thrust_n(), 4.0 * static_n]
	)


# ---------------------------------------------------------------------------
# Effect (a), and its edges
# ---------------------------------------------------------------------------

## TO MAKE THE MONOTONICITY CHECK FAIL: make the ratio read absf(mu), or drop the axial term.
## TO MAKE THE CLAMP CHECK FAIL: remove the `.max(0.0)` in `thrust_ratio_forward`. Past the advance
## where the blade stops pulling, BEMT reports NEGATIVE thrust, and an aircraft at speed is pulled
## backwards by its own propellers.
static func _thrust_falls_with_airspeed(build: Build) -> Array:
	var results: Array = []
	var geometry := build.prop_geometry()
	var ratios := build.forward_ratios()
	var rpm := 20000.0
	var static_n := PropellerModel.thrust_n(build.k_t, rpm)

	var previous := static_n
	var strictly_decreasing := true
	var reached_zero := false
	for i in range(1, 41):
		var v := float(i)
		var thrust := static_n * ratios.thrust_ratio(rpm, v, 0.0)
		if thrust > previous:
			strictly_decreasing = false
		if thrust <= 0.0:
			reached_zero = true
		previous = thrust

	results.append(TestResult.new(
		"thrust at a fixed RPM falls as the aircraft flies faster, and reaches zero",
		strictly_decreasing and reached_zero,
		"at %.0f RPM: %.2f N standing still, %.2f N at 40 m/s" % [rpm, static_n,
			static_n * ratios.thrust_ratio(rpm, 40.0, 0.0)]
	))

	# Well past the geometric advance, where an unclamped model is deeply negative.
	var far_past: float = 3.0 * PropellerModel.j_zero(geometry.diameter_m, geometry.pitch_m) \
		* (rpm / 60.0) * float(geometry.diameter_m)
	var beyond := static_n * ratios.thrust_ratio(rpm, far_past, 0.0)
	var factor := ratios.power_ratio(rpm, far_past, 0.0)
	results.append(TestResult.new(
		"past the geometric advance the model reports zero thrust, never negative and never NaN",
		beyond == 0.0 and not is_nan(factor) and factor > 0.0,
		"at %.1f m/s (3x J0): thrust %.3f N, power ratio %.4f" % [far_past, beyond, factor]
	))

	# The failure P6's closure found and fixed, kept as a permanent check. The power ratio used to
	# fall smoothly to 0.247 and then JUMP to 1.000 the moment BEMT's induced power went negative —
	# the guard returning the static answer, i.e. the model asserting that flying past your own
	# zero-thrust point costs exactly what hovering costs. On a 120 Hz tick that is a step in pack
	# current at a speed a fast build reaches.
	#
	# TO MAKE THIS FAIL: restore `if flight_p <= 0.0 { return 1.0 }` in `power_ratio_forward` in
	# place of the induced-power floor. Measured: the largest step jumps to 0.2697, against this bound of 0.10.
	var worst_step := 0.0
	var prev_ratio := ratios.power_ratio(rpm, 0.5, 0.0)
	for i in range(2, 161):
		var v := 0.5 * float(i)
		var r := ratios.power_ratio(rpm, v, 0.0)
		worst_step = maxf(worst_step, absf(r - prev_ratio))
		prev_ratio = r
	results.append(TestResult.new(
		"the power ratio is continuous through the zero-thrust crossing, with no step to hover cost",
		worst_step < 0.10,
		"largest change over a 0.5 m/s step across 0.5-80 m/s axial: %.4f" % worst_step
	))
	return results


# ---------------------------------------------------------------------------
# The shape of the answer
# ---------------------------------------------------------------------------

## The classical U-shaped rotorcraft power curve, and the single most load-bearing result in the
## whole slice: induced power falls with speed, parasite power rises, so current has a MINIMUM at
## neither end. Getting a curve of the right shape out of a hover-anchored model with one guessed
## constant is the strongest evidence available that the two effects are combined correctly.
##
## TO MAKE THIS FAIL: an effect-(a)-only model has its minimum at zero speed and fails the first
## half; a model with no parasite term never turns back up and fails the second.
static func _the_power_curve_has_a_minimum(build: Build) -> TestResult:
	var ceiling: float = build.peak_thrust()["throttle"]
	var at_rest := build.flight_current_at_a(0.0, 1.0, ceiling)
	var at_cruise := build.flight_current_at_a(CRUISE_MPS, 1.0, ceiling)
	var at_speed := build.flight_current_at_a(22.0, 1.0, ceiling)
	return TestResult.new(
		"the current-versus-airspeed curve dips and then climbs, rather than rising throughout",
		at_cruise < at_rest and at_cruise < at_speed,
		"0 m/s %.2f A -> %.1f m/s %.2f A -> 22 m/s %.2f A" % [
			at_rest, CRUISE_MPS, at_cruise, at_speed]
	)


## Descent is out of domain — vortex ring below the windmill-brake threshold, energy extraction
## above it — and the model returns the static answer rather than a confident wrong one.
##
## TO MAKE THIS FAIL: admit fast descents to the Glauert branch, which is what the first version of
## this guard did. `T*(V_axial + v_i)` with V_axial large and negative is negative shaft power, the
## factor goes negative, and a quad in a 30 m/s descent CHARGES ITS OWN PACK. That is not a
## hypothetical: it is how this was found, as a battery that gained charge during a test flight.
static func _descent_is_declined_rather_than_guessed(build: Build) -> TestResult:
	var ratios := build.forward_ratios()
	var rpm := 8500.0
	var worst := 1.0
	for i in range(1, 61):
		var factor := ratios.power_ratio(rpm, -float(i), 0.0)
		worst = minf(worst, factor)
	return TestResult.new(
		"no descent, however fast, produces negative power (a pack that charges itself)",
		worst == 1.0,
		"power factor over a 1-60 m/s descent never leaves 1.0 (min %.4f)" % worst
	)


## TO MAKE THIS FAIL: change Powertrain::step()'s delegation to pass anything but Vector3.ZERO.
## Every bench in the app predates this model and none of them has an aircraft.
static func _a_bench_is_the_static_path(build: Build) -> TestResult:
	var geometry := build.prop_geometry()
	var pt := Powertrain.create(build.motor_model(), build.k_t, build.k_q, build.battery_model(),
		build.effective_max_amps, build.rated_rpm(), build.pole_pairs(), geometry.blades,
		geometry.diameter_m * 0.5, geometry.pitch_m, build.air.kgm3(), build.blade_chord())
	for _i in 500:
		pt.step(PackedFloat64Array([0.5, 0.5, 0.5, 0.5]), 0.001)
	var rpm: float = pt.motor_rpm[0]
	var expected_n := PropellerModel.thrust_n(build.k_t, rpm)
	var published: float = pt.observables.thrust_n[0]
	return TestResult.new(
		"a bench still reads exactly k_t * omega^2, with no airspeed term anywhere in it",
		is_equal_approx(published, float(expected_n)) and pt.last_body_velocity_mps == Vector3.ZERO,
		"bench publishes %.6f N against static %.6f N at %.0f RPM" % [published, expected_n, rpm]
	)


# ---------------------------------------------------------------------------
# What the builder reads
# ---------------------------------------------------------------------------

## TO MAKE THE SECOND CHECK FAIL: average over the cruise row alone instead of the profile. Cruise
## is CHEAPER than hovering, so the reference build's predicted flight time goes to roughly eight
## minutes and busts physics.md §8's band — which is why steady cruise was rejected as the basis
## for this figure despite being the most defensible single number available.
static func _flight_time_comes_from_the_profile(build: Build) -> Array:
	var results: Array = []

	var fractions := 0.0
	for segment in Build.FREESTYLE_FLIGHT_PROFILE:
		fractions += float(segment["fraction"])
	results.append(TestResult.new(
		"the mission profile accounts for all of the flying time and none of it twice",
		is_equal_approx(fractions, 1.0),
		"%d segments summing to %.4f" % [Build.FREESTYLE_FLIGHT_PROFILE.size(), fractions]
	))

	var minutes := build.flight_time_min()
	results.append(TestResult.new(
		"the reference build's flight time lands inside physics.md's 4-6 minute band",
		minutes > 4.0 and minutes < 6.0,
		"%.2f min at %.2f A average (%.2fx its own hover current)" % [minutes,
			build.average_flight_current_a(),
			build.average_flight_current_a() / build.hover_current_a(build.hover_throttle())]
	))
	return results


## The honest result, and it is worth asserting BECAUSE it is a null one: at a fixed 45-degree lean
## the reference build needs 6.9 N and has 34 N available even fully unloaded, so the cap does not
## bind and the figure does not move. Asserting only this would be a test that cannot fail — which
## is exactly why the next one exists and why neither may be kept without the other.
static func _top_speed_is_unchanged_for_the_reference_build(build: Build) -> TestResult:
	var kmh := build.top_speed_kmh()
	return TestResult.new(
		"top speed for the reference build is unmoved, and still inside the 100-130 km/h band",
		absf(kmh - 108.2) < 1.0,
		"%.1f km/h" % kmh
	)


## The other half, and the one with teeth.
##
## TO MAKE THIS FAIL: evaluate top_speed_kmh()'s thrust ceiling at zero airspeed, as it was before.
## Measured: this check goes red at 79.4 km/h against a modelled 56.8, and the reference-build check
## above STAYS GREEN — one failure in a thousand. That is the trap made visible, and it is why
## neither of these two may be kept without the other.
##
## A REAL long-range build, not a contrivance: a 7-inch frame on 1507 motors turning 7x4 tri-blades
## off a 4S pack. Small motors on a big prop cannot rev, so the advance ratio climbs fast and the
## blades unload while the airframe still has plenty of drag left to push through. TWR is a healthy
## 3.07 — this is not a build that struggles to fly, it is one whose PROPELLER decides its top end,
## which is the diagnosis this whole term exists to make available.
static func _the_unloading_cap_binds_on_a_build_that_needs_it() -> TestResult:
	var catalog := PartsCatalog.load_default()
	var draggy := Build.from_ids(catalog, "frame_7in_long_range", "motor_1507_3600kv",
		"prop_7x4x3", "battery_4s_1500")

	var lean_horizontal_n := draggy.weight_n() * tan(Build.TOP_SPEED_LEAN_RAD)
	var drag_only_mps := sqrt(lean_horizontal_n / draggy.drag_coefficient)
	var modelled_mps := draggy.top_speed_kmh() / 3.6

	return TestResult.new(
		"a build whose props run out before its drag does reports the LOWER top speed",
		modelled_mps < drag_only_mps * 0.98,
		"drag alone says %.1f km/h; with unloading %.1f km/h" % [
			drag_only_mps * 3.6, modelled_mps * 3.6]
	)


## Phase 5: what changes on screen. Warn, never block, with severity (parts.md).
##
## The pair is the check, not either half. A warning that fires on everything is wallpaper and a
## warning that fires on nothing is dead code, so the same call is made against the build that
## should trip it and the one that should not.
##
## TO MAKE THIS FAIL: remove the _prop_unloading() line from warnings(). Both halves go at once,
## which is what a warning source disappearing should look like.
static func _the_builder_is_told_when_the_prop_is_the_limit(baseline: Build) -> Array:
	var catalog := PartsCatalog.load_default()
	var steep := Build.from_ids(catalog, "frame_7in_long_range", "motor_1507_3600kv",
		"prop_7x4x3", "battery_4s_1500")

	var warned: BuildWarning = null
	for warning in steep.warnings():
		if warning.id == &"prop_unloading":
			warned = warning
	var quiet := true
	for warning in baseline.warnings():
		if warning.id == &"prop_unloading":
			quiet = false

	return [
		TestResult.new(
			"a build whose top end is set by its propeller is told so, as a characteristic",
			warned != null and warned.severity == BuildWarning.Severity.CHARACTERISTIC
				and warned.message.contains("7x4x3"),
			"7\" long-range on 1507s: %s" % ("(no warning)" if warned == null else warned.message)),
		TestResult.new(
			"and the reference build, whose props have plenty left at its top speed, is not",
			quiet,
			"reference build carries no prop_unloading warning (props at %.0f%% of static thrust at %.0f km/h)" % [
				baseline.forward_ratios().thrust_ratio(baseline.max_rpm_at_nominal(),
					baseline.top_speed_kmh() / 3.6 * sin(Build.TOP_SPEED_LEAN_RAD),
					baseline.top_speed_kmh() / 3.6 * cos(Build.TOP_SPEED_LEAN_RAD)) * 100.0,
				baseline.top_speed_kmh()]),
	]
