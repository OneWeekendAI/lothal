extends SceneTree
## Tier 2 golden cross-check (design check 3). Each Rust fitting/plausibility function is
## compared against a VERBATIM transcription of the GDScript it replaces (build.gd,
## motor_plausibility.gd, prop_plausibility.gd, prop_extrapolation.gd). Run explicitly:
##   godot --headless --path . --script res://tests/rust_crosscheck_tier2.gd
## NOT part of the SUITES list in run_tests.gd.
##
## The reference functions below are the pre-port GDScript arithmetic, kept as the oracle;
## the call sites they came from now delegate to the Rust classes. A reference that silently
## drifts from what the code does would make this tautological, so the main suite's oracles
## (11.7:1, 29%, 496 g) are the second, independent gate.

func _init() -> void:
	var failures := 0
	failures += _check_fitting()
	failures += _check_plausibility()
	if failures == 0:
		print("TIER2 CROSSCHECK OK")
	else:
		print("%d TIER2 CROSSCHECK FAILURES" % failures)
	quit(1 if failures > 0 else 0)

func _cmp(got: float, want: float, label: String) -> int:
	var tol := 1e-12 + 1e-9 * maxf(absf(got), absf(want))
	if absf(got - want) > tol:
		print("MISMATCH %s rust=%.12f ref=%.12f" % [label, got, want])
		return 1
	return 0

# ---------------------------------------------------------------------------
# Reference transcriptions of the pre-port GDScript arithmetic.
# ---------------------------------------------------------------------------

static func _ref_throttle_limit_for(total_amps: float, full_throttle_amps: float) -> float:
	if full_throttle_amps <= 0.0 or total_amps <= 0.0:
		return 1.0
	return clampf(sqrt(total_amps / full_throttle_amps), 0.0, 1.0)

static func _ref_current_at_rpm(rpm: float, max_amps: float, rated_rpm: float) -> float:
	if rated_rpm <= 0.0:
		return 0.0
	var fraction := rpm / rated_rpm
	return max_amps * fraction * fraction

static func _ref_rpm_at_throttle(throttle: float, cap: float, kv: float, rest_v: float,
		internal_r: float, max_amps: float, rated_rpm: float) -> float:
	var t := clampf(throttle, 0.0, cap)
	var voltage_v := rest_v
	var rpm := 0.0
	for _i in 12:
		rpm = t * kv * voltage_v
		voltage_v = maxf(rest_v - _ref_current_at_rpm(rpm, max_amps, rated_rpm) * 4.0 * internal_r, 0.0)
	return rpm

static func _ref_limiting_index(motor: float, pack: float, esc: float) -> int:
	# candidates [motors, battery, esc]; strict minimum wins, ties keep the earlier.
	var binding := 0
	if pack < motor:
		binding = 1
	if esc < pack and esc < motor:
		binding = 2
	return binding

static func _ref_log_log_fit(xs: Array, ys: Array) -> Array:
	if xs.size() < 3:
		return [0.0, 0.0, 0.0, float(xs.size())]
	var mean_x := 0.0
	var mean_y := 0.0
	for i in xs.size():
		mean_x += xs[i]
		mean_y += ys[i]
	mean_x /= xs.size()
	mean_y /= ys.size()
	var covariance := 0.0
	var variance := 0.0
	for i in xs.size():
		covariance += (xs[i] - mean_x) * (ys[i] - mean_y)
		variance += (xs[i] - mean_x) * (xs[i] - mean_x)
	if variance <= 0.0:
		return [0.0, 0.0, 0.0, float(xs.size())]
	var exponent := covariance / variance
	var intercept := mean_y - exponent * mean_x
	var residual_high := 1.0
	for i in xs.size():
		residual_high = maxf(residual_high, exp(absf(ys[i] - (intercept + exponent * xs[i]))))
	return [exponent, exp(intercept), residual_high, float(xs.size())]

static func _ref_k_t_band(implied_kts: Array, widening: float) -> Array:
	var lowest := INF
	var highest := -INF
	var count := 0
	for k in implied_kts:
		if k <= 0.0:
			continue
		lowest = minf(lowest, k)
		highest = maxf(highest, k)
		count += 1
	if count == 0:
		return [0.0, INF, 0.0, 0.0, 0.0]
	return [lowest / widening, highest * widening, lowest, highest, float(count)]

# ---------------------------------------------------------------------------
# The comparisons.
# ---------------------------------------------------------------------------

func _check_fitting() -> int:
	var failures := 0
	# Smoke: the Rust classes must be reachable as static classes.
	if typeof(Fitting.throttle_limit_for(1.0, 1.0)) != TYPE_FLOAT:
		print("MISMATCH Fitting unusable (throttle_limit_for did not return a number)")
		return 1

	for total in [1.0, 30.0, 120.0, 200.0]:
		for full in [10.0, 45.0, 80.0, 160.0]:
			failures += _cmp(Fitting.throttle_limit_for(total, full),
				_ref_throttle_limit_for(total, full), "throttle_limit_for %f/%f" % [total, full])

	for kv in [600.0, 1400.0, 2600.0]:
		for tv in [14.8, 22.2]:
			failures += _cmp(Fitting.rated_rpm(kv, tv), kv * tv, "rated_rpm %f/%f" % [kv, tv])

	for throttle in [0.0, 0.29, 0.5, 0.75, 1.0]:
		for cap in [0.5, 0.8, 1.0]:
			for kv in [1400.0]:
				for rest_v in [14.8, 16.8]:
					for ir in [0.012, 0.05]:
						var r := Fitting.rpm_at_throttle(throttle, cap, kv, rest_v, ir, 45.0, 20720.0)
						var ref := _ref_rpm_at_throttle(throttle, cap, kv, rest_v, ir, 45.0, 20720.0)
						failures += _cmp(r, ref, "rpm_at_throttle t=%f cap=%f v=%f ir=%f" % [
							throttle, cap, rest_v, ir])

	# limiting_index: sweep strict-min tie-break cases.
	for m in [0.5, 0.8, 1.0]:
		for p in [0.5, 0.8, 1.0]:
			for e in [0.5, 0.8, 1.0]:
				failures += _cmp(float(Fitting.limiting_index(m, p, e)),
					float(_ref_limiting_index(m, p, e)),
					"limiting_index %f/%f/%f" % [m, p, e])
	return failures

func _check_plausibility() -> int:
	var failures := 0
	# Smoke.
	if typeof(Plausibility.log_log_fit(PackedFloat64Array([1.0, 2.0, 3.0]),
			PackedFloat64Array([1.0, 2.0, 3.0]))[0]) != TYPE_FLOAT:
		print("MISMATCH Plausibility unusable (log_log_fit did not return an array)")
		return 1

	# log_log_fit: a few point sets, including the <3 guard and a bad-fit case.
	var sets := [
		[[1.0, 2.0, 3.0, 4.0], [1.0, 4.0, 9.0, 16.0]],
		[[2.3, 2.7, 3.1, 3.5, 4.0], [7.0, 6.0, 5.0, 4.5, 4.0]],
		[[1.0, 2.0], [1.0, 2.0]],
	]
	for pts in sets:
		var xs := PackedFloat64Array(pts[0])
		var ys := PackedFloat64Array(pts[1])
		var rust: PackedFloat64Array = Plausibility.log_log_fit(xs, ys)
		var ref := _ref_log_log_fit(pts[0], pts[1])
		for i in 3:
			failures += _cmp(rust[i], ref[i], "log_log_fit[%d]" % i)

	# k_t_band across populations.
	for kts in [[2e-6, 3e-6, 4e-6], [1e-6, 0.0, 5e-6], []]:
		var rust: PackedFloat64Array = Plausibility.band_around(PackedFloat64Array(kts), 2.0)
		var ref := _ref_k_t_band(kts, 2.0)
		for i in 5:
			failures += _cmp(rust[i], ref[i], "k_t_band[%d]" % i)

	# extrapolation_factors is NOT transcribed here any more: P5 deleted the exponent law
	# (D⁴·blades^0.8·pitch^0.5) it validated and replaced it with the BEMT geometry ratio
	# (propulsion.md §0), which exists only in Rust — there is no pre-port GDScript arithmetic
	# to transcribe, and a transcription that called BemtModel would compare the function
	# against itself. The new law is validated by test_calibration.gd and by the held-out
	# points in test_validation.gd instead.
	return failures
