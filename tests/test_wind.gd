class_name TestWind
extends RefCounted
## The air itself moving (design §4.3): a steady offset, a seeded gust process, and the two places
## in `drone_core.gd` that read it — the powertrain's airspeed argument and the drag term — and
## nowhere else.
##
## THIRTEEN CHECKS, in three groups. §1 (checks 1-3) is the steady vector and its direction
## convention, against literals captured from the SHIPPED pre-F7 code — see check 1's comment for
## how, and why a golden value taken from the code it guards would be worthless. §2 (checks 4-11)
## is the wiring: does the powertrain actually see airspeed, does drag, does neither leak into
## `user://`. §3 (checks 12-13) is the two UI surfaces this slice also owns.
##
## Check 6 is the one that took the most work to get right, and it is worth saying why. At a FIXED
## throttle, MORE headwind measurably draws LESS current — translational lift makes the rotor
## cheaper (`test_forward_flight.gd` proves the same effect flying forward), which is the opposite
## of what "wind costs more" sounds like. What actually costs more is the THRUST a headwind demands
## to hold station against the drag it also creates — `sqrt(weight^2 + drag^2)` instead of just
## `weight` — and that demand eventually outweighs the translational-lift discount. So check 6
## trims DroneCore the same way `Build.flight_current_at_a()` already does (lean the airframe so
## thrust's horizontal component cancels the wind's drag, bisect throttle to the resulting target
## thrust) and drives it through `core.step()` — the REAL wind-wired path, not the standalone
## formula — at wind speeds chosen past the power curve's minimum, where the drag term has taken
## over. It comes out within a fraction of a percent of the pre-existing, independently-tested
## `flight_current_at_a()` oracle, which is the cross-check that the wiring is not merely present
## but correctly shaped.

const DT := 0.001   # 1 kHz, matching physics.md §6

## §1's literals — captured by running `ReferenceBuild.build_drone_core()` at hover throttle for a
## 5 s open-loop trajectory (no flight controller; constant hover-throttle commands on all four
## motors) AGAINST THE SHIPPED PRE-F7 CODE, at commit 1ca3538, before any of this file's
## implementation existed. Full precision (%.17f), so the comparison below is bit-for-bit rather
## than "close". A golden value taken from the implementation it is guarding is a test that cannot
## fail — this project has paid for that mistake three times — so these are frozen from the OLD
## code, which never heard of `Wind`.
const GOLDEN_POS := Vector3(0.00000000000000000, -48.30846786499023438, 21.69212913513183594)
const GOLDEN_VEL := Vector3(0.00000000000000000, -21.41524314880371094, -1.71378135681152344)
const GOLDEN_ANGVEL := Vector3(2.43456506729125977, 0.00000000000000000, 0.00000000000000000)
const GOLDEN_ORIENT := Quaternion(-0.06778866052627563, 0.00000000000000000, 0.00000000000000000,
	-0.99769967794418335)
const GOLDEN_GFORCE := 1.50548096947470689
const GOLDEN_CURRENT := 11.13983036513683267
const GOLDEN_AIRSPEED := 21.48370742797851562

static func run() -> Array:
	var results: Array = []
	# Taken BEFORE any other section runs — a GDScript dictionary literal evaluates its values
	# eagerly, in the order written, so "reproducibility" (which calls Wind.reset()) would already
	# have run by the time "authors nothing" built its OWN "before" snapshot otherwise, and a stray
	# write made during an earlier section would already be baked into both sides of that section's
	# own comparison. Measured: this was exactly the false-pass a `reset()`-writes-to-user://
	# mutation produced during this task's own mutation testing, before this line existed.
	var user_dir_before_any_section := _snapshot_user_dir()
	var sections := {
		"calm bit-identity": _calm_bit_identity(),
		"direction convention": _direction_convention(),
		"cardinal bearings": _cardinal_bearings(),
		"holding station in wind": _holding_station_in_wind(),
		"gust statistics": _gust_statistics(),
		"reproducibility": _reproducibility(),
		"zero gustiness": _zero_gustiness(),
		"authors nothing": _authors_nothing(user_dir_before_any_section),
		"gust tau field": _gust_tau_field(),
		"hud line": _hud_line(),
	}
	for label in sections:
		var section: Array = sections[label]
		results.append(TestResult.new(
			"section \"%s\" produced results" % label, not section.is_empty(),
			"%d checks" % section.size()))
		results.append_array(section)
	return results


# ---------------------------------------------------------------------------
# 1. Calm is bit-identical, and the direction convention
# ---------------------------------------------------------------------------

## Check 1. MUTATION THIS CATCHES: the offset applied unconditionally with a zero-length vector
## built as `Vector3(0, 0, 0.0001)` instead of the genuine `Vector3.ZERO` a calm `Conditions`
## produces — a stray ~0.0001 m/s leak that a loose tolerance would never notice, which is why the
## comparison below is exact equality against full-precision literals, not `is_equal_approx`.
static func _calm_bit_identity() -> Array:
	var results: Array = []
	var core := ReferenceBuild.build_drone_core()
	var calm := Conditions.new()   # wind_speed_mps, wind_from_deg, gustiness_mps all 0.0 by default
	core.wind = Wind.new(calm)
	var hover := ReferenceBuild.hover_throttle()
	core.prime_motors(hover)
	var cmds := {"M1": hover, "M2": hover, "M3": hover, "M4": hover}
	for _i in int(5.0 / DT):
		core.step(cmds, DT)

	results.append(TestResult.new(
		"calm conditions: position is bit-identical to the pre-F7 trajectory",
		core.rigid_body.position_m == GOLDEN_POS,
		"got %s, want %s" % [core.rigid_body.position_m, GOLDEN_POS]))
	results.append(TestResult.new(
		"calm conditions: velocity is bit-identical to the pre-F7 trajectory",
		core.rigid_body.velocity_mps == GOLDEN_VEL,
		"got %s, want %s" % [core.rigid_body.velocity_mps, GOLDEN_VEL]))
	results.append(TestResult.new(
		"calm conditions: angular velocity is bit-identical to the pre-F7 trajectory",
		core.rigid_body.angular_velocity_rad_s == GOLDEN_ANGVEL,
		"got %s, want %s" % [core.rigid_body.angular_velocity_rad_s, GOLDEN_ANGVEL]))
	results.append(TestResult.new(
		"calm conditions: orientation is bit-identical to the pre-F7 trajectory",
		core.rigid_body.orientation == GOLDEN_ORIENT,
		"got %s, want %s" % [core.rigid_body.orientation, GOLDEN_ORIENT]))
	results.append(TestResult.new(
		"calm conditions: the recorded log (g-force) is bit-identical to the pre-F7 trajectory",
		core.observables.g_force == GOLDEN_GFORCE,
		"got %.17f, want %.17f" % [core.observables.g_force, GOLDEN_GFORCE]))
	results.append(TestResult.new(
		"calm conditions: current is bit-identical to the pre-F7 trajectory",
		core.observables.current_total_a == GOLDEN_CURRENT,
		"got %.17f, want %.17f" % [core.observables.current_total_a, GOLDEN_CURRENT]))
	results.append(TestResult.new(
		"calm conditions: airspeed is bit-identical to the pre-F7 trajectory",
		core.observables.airspeed_mps == GOLDEN_AIRSPEED,
		"got %.17f, want %.17f" % [core.observables.airspeed_mps, GOLDEN_AIRSPEED]))
	# A core nobody ever hands a Wind to (wind == null, every caller before F7 and most tests
	# after it) must be the SAME calm flight, not a different code path that happens to agree.
	var bare_core := ReferenceBuild.build_drone_core()
	bare_core.prime_motors(hover)
	for _i in int(5.0 / DT):
		bare_core.step(cmds, DT)
	results.append(TestResult.new(
		"wind == null flies the identical calm trajectory as an explicit calm Wind",
		bare_core.rigid_body.position_m == core.rigid_body.position_m,
		"null-wind pos %s vs calm-Wind pos %s" % [bare_core.rigid_body.position_m,
			core.rigid_body.position_m]))
	return results


## Check 2. MUTATION THIS CATCHES: the `+ 180.0` inversion dropped from `steady_vector`.
static func _direction_convention() -> Array:
	var results: Array = []
	var v := Wind.steady_vector(5.0, 0.0)
	results.append(TestResult.new(
		"a north wind (from_deg = 0) moves the air toward +Z (\"south\" in this codebase's own " +
			"-Z-is-forward/-north convention)",
		is_equal_approx(v.z, 5.0),
		"steady_vector(5, 0) = %s, want z = +5.0" % v))
	results.append(TestResult.new(
		"a north wind has no east-west component",
		is_equal_approx(v.x, 0.0) and absf(v.x) < 1.0e-9,
		"steady_vector(5, 0).x = %.9f" % v.x))
	return results


## Check 3. Four cardinal bearings, four distinct axis-aligned vectors. MUTATION THIS CATCHES:
## `sin`/`cos` swapped in `steady_vector` — verified by hand-editing wind.gd to swap them and
## re-running this suite (see the report for the paste of that run), then reverting.
static func _cardinal_bearings() -> Array:
	var results: Array = []
	var speed := 5.0
	var cases := {
		0.0: Vector3(0.0, 0.0, speed),      # north wind -> blows south (+Z)
		90.0: Vector3(-speed, 0.0, 0.0),    # east wind -> blows west (-X)
		180.0: Vector3(0.0, 0.0, -speed),   # south wind -> blows north (-Z)
		270.0: Vector3(speed, 0.0, 0.0),    # west wind -> blows east (+X)
	}
	for from_deg in cases:
		var want: Vector3 = cases[from_deg]
		var got := Wind.steady_vector(speed, from_deg)
		results.append(TestResult.new(
			"from_deg = %.0f gives an axis-aligned vector of the right magnitude" % from_deg,
			got.is_equal_approx(want),
			"got %s, want %s" % [got, want]))

	# Distinctness: no two of the four collapse onto the same vector.
	var vectors: Array = cases.values().map(func(_v: Variant) -> Vector3: return Vector3.ZERO)
	var i := 0
	for from_deg in cases:
		vectors[i] = Wind.steady_vector(speed, from_deg)
		i += 1
	var all_distinct := true
	for a in vectors.size():
		for b in range(a + 1, vectors.size()):
			if (vectors[a] as Vector3).is_equal_approx(vectors[b] as Vector3):
				all_distinct = false
	results.append(TestResult.new(
		"the four cardinal bearings map to four DISTINCT vectors",
		all_distinct,
		"vectors: %s" % [vectors]))

	# `wind_from_deg` is never normalised on the way in (conditions.gd's header) — 370 must behave
	# exactly like 10.
	results.append(TestResult.new(
		"steady_vector is not normalised: 370 deg behaves exactly like 10 deg",
		Wind.steady_vector(5.0, 370.0).is_equal_approx(Wind.steady_vector(5.0, 10.0)),
		"370: %s, 10: %s" % [Wind.steady_vector(5.0, 370.0), Wind.steady_vector(5.0, 10.0)]))
	return results


# ---------------------------------------------------------------------------
# 2. The wiring: powertrain, drag, statistics, reproducibility, user://
# ---------------------------------------------------------------------------

static func _headwind_conditions(speed: float) -> Conditions:
	var c := Conditions.new()
	c.wind_speed_mps = speed
	c.wind_from_deg = 0.0
	c.gustiness_mps = 0.0
	return c

## Checks 4 and 5. MUTATIONS THIS CATCHES: check 4's is "the wind subtracted in the body frame
## before rotation" — the effect of doing that at this LEVEL orientation is nil (rotation by
## IDENTITY changes nothing), so this pair is corroborated by `_holding_station_in_wind()` below,
## which trims at a genuine lean where a before/after-rotation bug WOULD show up as a different
## number. Check 5's is "the sign of the subtraction flipped" — caught directly below: flipping the
## sign turns a downwind-at-wind-speed drone's airspeed from 0 into 2x the wind speed.
static func _holding_station_in_wind() -> Array:
	var results: Array = []
	var hover := ReferenceBuild.hover_throttle()
	var cmds := {"M1": hover, "M2": hover, "M3": hover, "M4": hover}

	# Check 4: stationary, level, 7 m/s headwind — the powertrain must read exactly 7 m/s.
	var core := ReferenceBuild.build_drone_core()
	core.wind = Wind.new(_headwind_conditions(7.0))
	core.rigid_body.velocity_mps = Vector3.ZERO
	core.prime_motors(hover)
	core.step(cmds, DT)
	results.append(TestResult.new(
		"a stationary drone in a 7 m/s headwind sees 7 m/s of airspeed at the powertrain",
		is_equal_approx(core.powertrain.last_body_velocity_mps.length(), 7.0),
		"powertrain saw %s (length %.4f)" % [core.powertrain.last_body_velocity_mps,
			core.powertrain.last_body_velocity_mps.length()]))

	# Check 5: moving downwind at exactly the wind's own speed — zero airspeed.
	var downwind_vec := Wind.steady_vector(7.0, 0.0)   # the direction and speed the air moves
	var core2 := ReferenceBuild.build_drone_core()
	core2.wind = Wind.new(_headwind_conditions(7.0))
	core2.rigid_body.velocity_mps = downwind_vec
	core2.prime_motors(hover)
	core2.step(cmds, DT)
	results.append(TestResult.new(
		"a drone moving downwind at exactly the wind's speed sees zero airspeed",
		core2.powertrain.last_body_velocity_mps.length() < 1.0e-6,
		"powertrain saw %s (length %.8f)" % [core2.powertrain.last_body_velocity_mps,
			core2.powertrain.last_body_velocity_mps.length()]))

	# Check 6: holding station costs more current than calm, and the excess GROWS with wind speed.
	# See the class header for why 15/18/22 m/s rather than a gentler trio: at a fixed throttle,
	# moderate headwinds draw LESS current (translational lift), and only past the power curve's
	# minimum does the extra thrust demanded to hold station against drag start to dominate.
	var build := ReferenceBuild.build()
	var hover_current := build.hover_current_a(build.hover_throttle())
	var ceiling: float = build.peak_thrust()["throttle"]
	var speeds := [15.0, 18.0, 22.0]
	var currents: Array[float] = []
	var oracle_currents: Array[float] = []
	for speed in speeds:
		currents.append(_trimmed_current_holding_station(build, speed, ceiling))
		oracle_currents.append(build.flight_current_at_a(speed, 1.0, ceiling))

	var all_above_hover := true
	for c in currents:
		if c <= hover_current:
			all_above_hover = false
	results.append(TestResult.new(
		"holding station at 15/18/22 m/s of wind costs more current than calm hover",
		all_above_hover,
		"hover %.3f A; windy %s A" % [hover_current, currents]))

	var monotonic := currents[0] < currents[1] and currents[1] < currents[2]
	results.append(TestResult.new(
		"the excess current GROWS with wind speed (15/18/22 m/s, monotonic)",
		monotonic,
		"currents at 15/18/22 m/s: %s" % [currents]))

	# Cross-checked against the pre-existing, independently-tested flight_current_at_a() oracle —
	# not because the two MUST agree (one trims through the real wind-wired DroneCore.step(), the
	# other is a closed-form solve), but because close agreement is strong evidence the wiring is
	# shaped correctly rather than merely present. This is also what catches check 6's stated
	# mutation ("wind reaches drag but not the powertrain"): drop wind from the powertrain and the
	# bisection converges on a throttle that needs no unloading correction, landing measurably off
	# this oracle.
	var worst_relative_error := 0.0
	for i in currents.size():
		var relative_error: float = absf(currents[i] - oracle_currents[i]) / oracle_currents[i]
		worst_relative_error = maxf(worst_relative_error, relative_error)
	results.append(TestResult.new(
		"the DroneCore-trimmed current agrees with flight_current_at_a() to within 1%",
		worst_relative_error < 0.01,
		"DroneCore %s vs oracle %s (worst relative error %.4f%%)" % [
			currents, oracle_currents, worst_relative_error * 100.0]))
	return results


## Trims DroneCore to hold station against a headwind: lean the airframe so thrust's horizontal
## component cancels the wind's drag (the SAME lean/target-thrust decomposition
## `Build.flight_current_at_a()` uses), then bisect throttle — through a REAL `core.step()` each
## trial, so the wind actually has to reach both the powertrain and the drag term for this to
## converge on the right answer — until the resulting thrust matches the target.
static func _trimmed_current_holding_station(build: Build, wind_speed: float,
		throttle_ceiling: float) -> float:
	var weight_n := build.weight_n()
	var drag_n: float = build.drag_coefficient * wind_speed * wind_speed
	# Negative: this codebase's lean-right-of-north sign for a Vector3(1,0,0)-axis rotation cancels
	# a +Z drag force (the direction a from_deg = 0 wind blows an object) rather than adding to it
	# — checked by hand against a probe run, not derived here a second time.
	var lean_rad: float = -atan2(drag_n, weight_n)
	var target_n: float = sqrt(weight_n * weight_n + drag_n * drag_n)

	var conditions := _headwind_conditions(wind_speed)
	var cmds_at := func(throttle: float) -> Dictionary:
		return {"M1": throttle, "M2": throttle, "M3": throttle, "M4": throttle}

	var low := 0.0
	var high := throttle_ceiling
	var current := 0.0
	for _i in 30:
		var mid := (low + high) * 0.5
		var core := ReferenceBuild.build_drone_core()
		core.wind = Wind.new(conditions)
		core.rigid_body.orientation = Quaternion(Vector3(1, 0, 0), lean_rad)
		core.rigid_body.velocity_mps = Vector3.ZERO
		core.prime_motors(mid)
		core.step(cmds_at.call(mid), DT)
		var thrust: PackedFloat32Array = core.powertrain.observables.thrust_n
		var total_thrust := thrust[0] + thrust[1] + thrust[2] + thrust[3]
		current = core.observables.current_total_a
		if total_thrust < target_n:
			low = mid
		else:
			high = mid
	return current


## Checks 7 and 8: the gust process's statistics, measured, not merely asserted to pass.
##
## Sampled 60 s at 100 Hz (6000 samples/axis) as check 7 itself specifies. THE FIRST ATTEMPT AT
## THIS, using only ONE axis (x), measured 13.1% off on the standard deviation and 23.7% off on the
## autocorrelation time against the DEFAULT_SEED stream — outside the stated tolerances, not
## because the formula is wrong but because 60 s / 2.5 s-tau is only ~24 independent gust cycles,
## which is genuinely a small sample for a lag-1 autocorrelation estimator. `Wind` draws x, y and z
## as three INDEPENDENT AR(1) streams from the same seeded RNG (not three views of one number), so
## pooling all three axes' samples is legitimate extra statistical power from the SAME 60 s of
## process, not a longer run or a friendlier seed — it brought both figures to within 3%. See the
## report for the one-axis numbers this replaced, pasted alongside these.
static func _gust_statistics() -> Array:
	var results: Array = []
	var gustiness := 3.0
	var dt := 0.01   # 100 Hz — coarser than the 1 kHz physics loop, chosen for run time; the PT1
					  # coefficient a = dt/(tau+dt) does not care what dt is.
	var duration_s := 60.0
	var steps := int(duration_s / dt)

	# Check 7: standard deviation, pooled across the three independent axes.
	var conditions := Conditions.new()
	conditions.gustiness_mps = gustiness
	var axes := _sample_axes(conditions, Wind.DEFAULT_GUST_TAU_S, dt, steps)
	var pooled: Array[float] = []
	pooled.append_array(axes[0])
	pooled.append_array(axes[1])
	pooled.append_array(axes[2])
	var measured_sd := _standard_deviation(pooled)
	var sd_relative_error := absf(measured_sd - gustiness) / gustiness
	results.append(TestResult.new(
		"the gust process's measured standard deviation is within 10%% of gustiness_mps",
		sd_relative_error < 0.10,
		"measured SD = %.4f m/s over %d pooled samples (3 axes x %d), gustiness_mps = %.4f (%.1f%% off)"
			% [measured_sd, pooled.size(), steps, gustiness, sd_relative_error * 100.0]))

	# Check 8: autocorrelation time, averaged across the three axes, and that doubling tau roughly
	# doubles it. The process is an exact discrete AR(1) (rate += (drive - rate) * a), so its lag-1
	# autocorrelation rho is exactly `tau / (tau + dt)` in expectation — inverted here as
	# `tau_measured = dt * rho / (1 - rho)`.
	var measured_tau := (_autocorrelation_time(axes[0], dt) + _autocorrelation_time(axes[1], dt)
		+ _autocorrelation_time(axes[2], dt)) / 3.0
	var tau_relative_error := absf(measured_tau - Wind.DEFAULT_GUST_TAU_S) / Wind.DEFAULT_GUST_TAU_S
	results.append(TestResult.new(
		"the gust process's measured autocorrelation time is within 20%% of gust_tau_s",
		tau_relative_error < 0.20,
		"measured tau = %.4f s (averaged over 3 axes), gust_tau_s = %.4f s (%.1f%% off)" % [
			measured_tau, Wind.DEFAULT_GUST_TAU_S, tau_relative_error * 100.0]))

	var double_tau := Wind.DEFAULT_GUST_TAU_S * 2.0
	var axes2 := _sample_axes(conditions, double_tau, dt, steps)
	var measured_tau2 := (_autocorrelation_time(axes2[0], dt) + _autocorrelation_time(axes2[1], dt)
		+ _autocorrelation_time(axes2[2], dt)) / 3.0
	var doubling_ratio := measured_tau2 / measured_tau
	results.append(TestResult.new(
		"doubling gust_tau_s roughly doubles the measured autocorrelation time",
		doubling_ratio > 1.6 and doubling_ratio < 2.4,
		"tau = %.2f s measured %.4f s; tau = %.2f s measured %.4f s (ratio %.3f)" % [
			Wind.DEFAULT_GUST_TAU_S, measured_tau, double_tau, measured_tau2, doubling_ratio]))
	return results


## A fresh Wind built at the given tau, stepped `steps` times, returning its three axes as
## separate sample arrays — [xs, ys, zs].
static func _sample_axes(conditions: Conditions, gust_tau_s: float, dt: float,
		steps: int) -> Array:
	var wind := Wind.new(conditions, gust_tau_s)
	var xs: Array[float] = []
	var ys: Array[float] = []
	var zs: Array[float] = []
	for _i in steps:
		var v := wind.update(dt)
		xs.append(v.x)
		ys.append(v.y)
		zs.append(v.z)
	return [xs, ys, zs]


static func _standard_deviation(samples: Array[float]) -> float:
	var mean := 0.0
	for s in samples:
		mean += s
	mean /= samples.size()
	var variance := 0.0
	for s in samples:
		variance += (s - mean) * (s - mean)
	variance /= samples.size()
	return sqrt(variance)


## Lag-1 sample autocorrelation, inverted to a time constant per the AR(1) closed form in
## `_gust_statistics()`'s comment.
static func _autocorrelation_time(samples: Array[float], dt: float) -> float:
	var mean := 0.0
	for s in samples:
		mean += s
	mean /= samples.size()
	var numerator := 0.0
	var denominator := 0.0
	for i in samples.size() - 1:
		numerator += (samples[i] - mean) * (samples[i + 1] - mean)
	for s in samples:
		denominator += (s - mean) * (s - mean)
	var rho := numerator / denominator
	if rho <= 0.0 or rho >= 1.0:
		return 0.0   # degenerate; the caller's tolerance will fail this loudly rather than /0
	return dt * rho / (1.0 - rho)


## Check 9. MUTATION THIS CATCHES: the RNG left unseeded (drawing from an ambient/global stream) —
## two objects built the SAME way would then diverge from the first sample.
static func _reproducibility() -> Array:
	var results: Array = []
	var conditions := Conditions.new()
	conditions.gustiness_mps = 2.0
	var a := Wind.new(conditions)
	var b := Wind.new(conditions)
	var identical := true
	for _i in 500:
		if a.update(0.01) != b.update(0.01):
			identical = false
			break
	results.append(TestResult.new(
		"two Wind objects with the same seed produce an identical gust sequence",
		identical,
		"diverged: %s" % (not identical)))

	# reset() replays the same stream rather than continuing the old one.
	var c := Wind.new(conditions)
	var first_run: Array[Vector3] = []
	for _i in 50:
		first_run.append(c.update(0.01))
	c.reset()
	var replayed := true
	for i in 50:
		if c.update(0.01) != first_run[i]:
			replayed = false
			break
	results.append(TestResult.new(
		"reset() replays the identical gust sequence rather than continuing the old stream",
		replayed,
		"replay diverged: %s" % (not replayed)))
	return results


## Check 10. MUTATION THIS CATCHES: a stray non-zero offset leaking in even at gustiness_mps = 0 —
## demonstrated the same way check 1's is: the honest finding is that under the ACTUAL formula
## (sigma = gustiness_mps * sqrt((2-a)/a)), gustiness_mps = 0 forces sigma to exactly 0.0 and the
## process is zero by construction, with or without a special-cased early return — see the report.
## This check is kept anyway because "zero gustiness produces exactly the steady vector" is a real
## claim about the shipped code's behaviour, worth asserting even where the arithmetic guarantees
## it; the report says plainly that this one could not be made to fail by any mutation that leaves
## the amplitude formula itself intact.
static func _zero_gustiness() -> Array:
	var results: Array = []
	var conditions := Conditions.new()
	conditions.wind_speed_mps = 4.0
	conditions.wind_from_deg = 45.0
	conditions.gustiness_mps = 0.0
	var wind := Wind.new(conditions)
	var steady := Wind.steady_vector(4.0, 45.0)
	var all_exact := true
	for _i in 1000:
		if wind.update(0.001) != steady:
			all_exact = false
			break
	results.append(TestResult.new(
		"zero gustiness produces exactly the steady vector, every step",
		all_exact,
		"first divergence within 1000 steps: %s" % (not all_exact)))
	return results


## Check 11. `Sim authors nothing`: `Wind` must never write to `user://`. MUTATION THIS CATCHES: a
## line that caches gust state to a `user://` path — this snapshot-and-diff would show a new file
## or a changed mtime/size.
static func _authors_nothing(before: Dictionary) -> Array:
	var results: Array = []
	var conditions := Conditions.new()
	conditions.gustiness_mps = 3.0
	var wind := Wind.new(conditions)
	var steps := int(60.0 / 0.01)
	for _i in steps:
		wind.update(0.01)
	wind.reset()
	wind.velocity_mps()
	var after := _snapshot_user_dir()
	results.append(TestResult.new(
		"Wind writes nothing under user:// across a 60 s run",
		before == after,
		"before: %d entries, after: %d entries%s" % [before.size(), after.size(),
			"" if before == after else " (DIFFERS)"]))
	return results


## path -> [size, modified_unix_time], recursively, under user://. A plain-data snapshot rather
## than a hash, because a changed size or mtime is already proof enough and this runs inside a
## test loop.
static func _snapshot_user_dir(path: String = "user://") -> Dictionary:
	var out := {}
	var dir := DirAccess.open(path)
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry != "." and entry != "..":
			var full := path.path_join(entry)
			if dir.current_is_dir():
				out.merge(_snapshot_user_dir(full))
			else:
				out[full] = [FileAccess.get_file_as_bytes(full).size(),
					FileAccess.get_modified_time(full)]
		entry = dir.get_next()
	dir.list_dir_end()
	return out


# ---------------------------------------------------------------------------
# 3. The two UI surfaces
# ---------------------------------------------------------------------------

## Check 12. `gust_tau_s` is reachable as an editable field, and its shipped value is labelled a
## guess in the UI text (Ruling 50). MUTATION THIS CATCHES: the label calls it measured.
static func _gust_tau_field() -> Array:
	var results: Array = []
	# RE-POINTED IN F11: the field editor is retired and the gust field moved into the Field room
	# with the rest of the authoring. Same control, same claim, same wording.
	var room := FieldSystem.new(
		SiteLibrary.with_default(), CourseLibrary.with_default(),
		ConditionsLibrary.with_default(), ReferenceBuild.build(),
		"user://test_wind_courses.json")

	results.append(TestResult.new(
		"gust_tau_s is reachable as an editable field, at the shipped default",
		is_equal_approx(room.gust_tau_s, Wind.DEFAULT_GUST_TAU_S)
			and is_equal_approx(room.gust_tau_field.value, Wind.DEFAULT_GUST_TAU_S),
		"room.gust_tau_s = %.4f, field.value = %.4f, Wind.DEFAULT_GUST_TAU_S = %.4f" % [
			room.gust_tau_s, room.gust_tau_field.value, Wind.DEFAULT_GUST_TAU_S]))

	# The field actually takes an edit — driven through set_field_gust_tau_s(), the same method the
	# SpinBox's on_change callback calls (a Range's value_changed signal does not reliably fire on
	# a control that was never added to a SceneTree, so this repo's tests drive the method).
	room.set_field_gust_tau_s(4.2)
	results.append(TestResult.new(
		"editing the field changes gust_tau_s",
		is_equal_approx(room.gust_tau_s, 4.2),
		"room.gust_tau_s = %.4f after set_field_gust_tau_s(4.2)" % room.gust_tau_s))

	# The label text itself, read off the LIVE control rather than grepped from the source file — a
	# source-wide grep for "guess" would also match this very file's own doc comments (this class's
	# header uses the word too), which is a check that cannot fail against the stated mutation. The
	# live Label's text is exactly what a builder reads, and nothing else.
	var label_text: String = room.gust_tau_label.text
	results.append(TestResult.new(
		"the shipped gust settle time is labelled a GUESS, not measured, in the UI text",
		label_text.to_lower().contains("guess"),
		"gust label reads: \"%s\"" % label_text))
	room.free()
	return results


## Check 13. The HUD states wind speed and direction WITH UNITS, and never grades it. MUTATION THIS
## CATCHES: the HUD adds a phrase like "strong for this build".
const FORBIDDEN_WIND_WORDS := ["too windy", "strong for this build", "dangerous", "unsafe",
	"not recommended", "difficult"]

static func _hud_line() -> Array:
	var results: Array = []
	var hud := Hud.new()
	var core := ReferenceBuild.build_drone_core()
	var conditions := Conditions.new()
	conditions.wind_speed_mps = 6.3
	conditions.wind_from_deg = 225.0
	core.wind = Wind.new(conditions)
	core.prime_motors(ReferenceBuild.hover_throttle())

	var build := ReferenceBuild.build()
	var course := GateCourse.new()
	var timer := LapTimer.new(course.fingerprint(), "user://test_wind_lap.json")
	hud.render(core, build, course, timer, false)

	var wind_text: String = hud._wind_label.text
	results.append(TestResult.new(
		"the HUD states wind speed with units",
		wind_text.contains("m/s") and wind_text.contains("6.3"),
		"HUD wind line: \"%s\"" % wind_text))
	results.append(TestResult.new(
		"the HUD states wind direction with units",
		wind_text.contains("°") or wind_text.contains("deg"),
		"HUD wind line: \"%s\"" % wind_text))

	var lower := wind_text.to_lower()
	var found_forbidden := ""
	for word in FORBIDDEN_WIND_WORDS:
		if lower.contains(word):
			found_forbidden = word
	results.append(TestResult.new(
		"the HUD wind line never grades the wind (no forbidden word found)",
		found_forbidden == "",
		"forbidden word found: \"%s\" in \"%s\"" % [found_forbidden, wind_text]))

	# No wind at all: the HUD must still render something sane rather than crash.
	var bare_core := ReferenceBuild.build_drone_core()
	bare_core.prime_motors(ReferenceBuild.hover_throttle())
	hud.render(bare_core, build, course, timer, false)
	results.append(TestResult.new(
		"a core with no Wind (wind == null) does not crash the HUD",
		true,   # reaching this line at all is the assertion
		"render() with wind == null returned normally"))
	return results
