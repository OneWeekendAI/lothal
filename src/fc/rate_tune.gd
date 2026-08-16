class_name RateTune
extends RefCounted
## The inner loop's gains, DERIVED FROM THE AIRCRAFT THEY ARE FLYING rather than typed in once and
## handed to everything (labs-and-sim.md §7, resolved).
##
## ---------------------------------------------------------------------------
## WHAT WAS WRONG
## ---------------------------------------------------------------------------
##
## RateModeController carried one gain set and gave it to every build in the catalog. Measured on
## one carried build, so that the frame is the only thing that differs, settled roll acceleration
## runs 1037 rad/s^2 on the 65 mm whoop down to 212 on the 10" long-range, and settled YAW
## acceleration runs 422 down to 13.9 — a factor of THIRTY on one axis. A rate loop's gains scale
## with the plant they close on. One gain set across that is not a tune that is slightly off at the
## ends; it is a tune that is correct for one aircraft and shipped with twelve.
##
## What it cost, measured on a small-signal step where the loop is the only thing under test:
## yaw overshoot ran from 1.3% on the 10" to 64.6% on the whoop, against the reference build's
## 12.7%. The whoop was not "a bit twitchy in yaw" — it was ringing, on gains that are correct for
## an aircraft with an eighth of its yaw authority. And a builder judging that whoop was judging
## the tune's mismatch rather than the design's character, which is the one thing Lothal exists not
## to do.
##
## ---------------------------------------------------------------------------
## THE LAW, AND WHAT IT HOLDS CONSTANT
## ---------------------------------------------------------------------------
##
## The PID works on NORMALISED quantities: RateModeController divides the measured rate by
## MAX_RATE_RAD_S, and its output goes to the mixer as a fraction of full command. So write the
## plant in those units. A command of 1.0 on an axis buys that axis's settled angular acceleration
## `A` (rad/s^2), and a normalised rate of 1.0 is MAX_RATE_RAD_S, so
##
##     d(normalised rate)/dt = (A / MAX_RATE_RAD_S) * command
##
## and `g = A / MAX_RATE_RAD_S` is the loop gain the controller actually sees, in 1/s. With P alone
## the closed loop is first order:
##
##     tau = 1 / (g * kp) = MAX_RATE_RAD_S / (A * kp)
##
## **The quantity held constant across the catalog is tau, the closed-loop time constant.** Which
## gives kp * A = constant, so kp scales as 1/A. That is the whole law, and it is one line — but
## WHY tau is the right thing to hold constant is the part worth writing down, because two other
## choices look just as reasonable and are both wrong.
##
## The loop does not close on the airframe alone. It closes on the airframe THROUGH a chain of lags
## that have nothing to do with the airframe: the motor's electrical time constant (~30 ms), the
## gyro's PT1 (1.06 ms at the stock 150 Hz cutoff), the sensor's zero-order hold, and the 1 kHz
## substep. Every one of those is a FIXED TIME. They do not get shorter on a whoop or longer on a
## 10". Stability is set by how the loop's own time constant compares to them — and holding tau
## constant is exactly what keeps that comparison, and therefore the phase margin, the same on
## every aircraft in the catalog.
##
## Hold something else and it does not. Scaling tau with the airframe (a "faster aircraft gets a
## faster loop" rule, which sounds right) would put the whoop's loop at 5.9 ms against a 1.06 ms
## filter and a 30 ms motor, and that is the ringing described above. Holding the raw gain constant
## is what the code did before, and it is the same failure from the other end. Tau is the only one
## of the three that is dimensionally the same kind of thing as the lags it has to survive.
##
## From tau, the other two gains follow with no further choice to make:
##
## - **ki scales with kp**, because the integral TIME CONSTANT kp/ki is what sets the character and
##   holding tau means holding it too. rate_mode_controller.gd already says this, for one axis:
##   "the ratio is what sets the character, the absolute values follow the authority." That
##   sentence IS this law, written down before there was a law. This class generalises it rather
##   than overwriting it.
## - **kd scales with kp**, because the damping the loop actually gets is g*kd — put D into the
##   first-order form above and the closed loop becomes (1 + g*kd) * dy/dt = g*kp*e, so g*kd is the
##   dimensionless damping and holding it constant means kd goes as 1/A like everything else.
##
## So it is ONE scale factor per axis, `A_reference / A_this_build`, applied to all three gains.
## Which is a considerably duller answer than the problem deserved, and that is the finding.
##
## ---------------------------------------------------------------------------
## THE ANCHOR
## ---------------------------------------------------------------------------
##
## The reference build must come out at EXACTLY today's hand-tuned gains — 2.3 / 0.15 / 0.042 on
## roll and pitch, 6.0 / 0.39 / 0.0 on yaw. Not approximately. The law is normalised so that the
## aircraft the gains were found on reproduces them and every other build moves relative to it,
## which is what makes this a scaling slice rather than a retune: tests/test_rate_step_response.gd,
## test_rate_mode_release.gd, test_stick_release.gd, test_control_path.gd and
## test_flight_controller.gd all encode the current tune's behaviour and all pass untouched.
##
## Exactness is free rather than lucky. The divisor is the reference build's own plant figure taken
## through this same function, so the reference's scale factor is A_ref/A_ref — 1.0 in floating
## point, not 0.9999999.
##
## ---------------------------------------------------------------------------
## THERE IS NO GAIN CEILING, AND THE SLEW ARGUMENT IS WHY
## ---------------------------------------------------------------------------
##
## rate_mode_controller.gd stops yaw's kp at 6.0 because "above about 6 the loop is waiting on the
## airframe": a 500 deg/s yaw step is SLEW-limited, and sweeping kp from 6.5 to 9.0 moved settling
## by 2 ms. The obvious reading is that 6.0 is a ceiling, and that a low-authority yaw axis must not
## be scaled past it. That reading was tested and it is wrong, twice over.
##
## First, the diminishing return is not a property of the airframe. Settling time is the slew floor
## plus the loop's share, and both go as 1/A:
##
##     settle ~ (1/A) * (target_rate + c * MAX_RATE_RAD_S / kp)
##
## so the FRACTION of settling that more gain can buy back depends on kp and the step amplitude and
## not on A at all. Every aircraft in the catalog hits the same diminishing return at the same kp,
## on the same size of step. A ceiling at 6.0 would therefore not be protecting low-authority
## airframes from anything; it would be freezing them at a gain chosen for a different plant, which
## is the bug this class exists to fix.
##
## Second, it was measured. Sweeping the 10" long-range's yaw from the capped 6.0 to the law's own
## 24.35 gives, on a 500 deg/s step, settling 722 -> 637 ms with overshoot 0.23 -> 1.27%; and on a
## 50 deg/s step, 409 -> 211 ms with overshoot 1.32 -> 10.75%. Both land on the reference build's
## own figures. Nothing rings, nothing oscillates, and the capped version is simply slower.
##
## What the original observation actually says, restated: **6.0 is not a ceiling, it is where the
## law puts the reference aircraft.** "More gain buys nothing above 6" was measured ON the
## reference, where the tune was already correct — which is a confirmation of the anchor, not a
## bound on the catalog. And the underlying truth survives intact and unscaled: at large stick
## deflections the airframe, not the gain, sets the settling time, on every aircraft equally. The
## 10" still needs 637 ms for a full-stick yaw reversal, because 624 ms of that is its slew floor
## and no tune touches it.
##
## The invariant is the stability guarantee. tau is held at the hand-tuned aircraft's value, so no
## derived gain can outrun the fixed lags; there is nothing left for a ceiling to protect against.
##
## ---------------------------------------------------------------------------
## EXCEPT D, WHICH THE BOARD BOUNDS
## ---------------------------------------------------------------------------
##
## D acts on the difference between successive gyro readings, so it multiplies the sensor's noise
## floor — and since the FC slice, that floor is a property of the board you fitted rather than a
## project constant. A D scaled up for a big airframe on a cheap gyro is a motor heater.
##
## So the derived kd has a ceiling that depends on the FC, and crossing it says so, at `limiting`,
## naming the board. The arithmetic is FcDetails' own, reached through this class rather than
## copied, because that panel and this tune quoting different numbers for the same noise is exactly
## the divergence ROLL_PITCH_KD was named to prevent.

## What fraction of full command the D term may spend on gyro noise, RMS, with the aircraft
## perfectly still.
##
## THIS IS A CHOSEN LINE AND IT IS STATED AS ONE — there is no threshold in the physics to point at,
## because D-term noise degrades continuously into motor heat rather than crossing a boundary. What
## can be done honestly is to say where it was put and against what:
##
## - The reference build on its own board sits at 0.47%, so the anchor has better than four times
##   the headroom and this ceiling can never move the hand tune. That is a requirement, not a
##   coincidence: a bound that constrained the aircraft the gains were found on would be describing
##   a tune nobody has flown.
## - The NOISIEST board in the catalog — the F411 whoop board, an MPU-6000 sampled at 8 kHz —
##   already sits at 2.03% carrying the reference D gain unscaled. So 2% is where the catalog's own
##   worst case falls, which makes this the line the FC slice drew when it put that figure on the
##   details panel rather than a second opinion about it. Past here, the board's noise rather than
##   the airframe is deciding the tune, and that is worth being told.
## - Lothal models no D-term lowpass, which real Betaflight has. So the figure this is compared
##   against is an upper bound on what a real board would show, and the ceiling inherits that.
const D_NOISE_BUDGET := 0.02

const AXIS_NAMES := ["roll", "pitch", "yaw"]

## Per-axis, in the coordinate contract's order — Vector3(roll, pitch, yaw), matching FrameBench's
## AXIS_ROLL / AXIS_PITCH / AXIS_YAW and the setpoint vector the loop is handed.
var kp := Vector3.ZERO
var ki := Vector3.ZERO
var kd := Vector3.ZERO

## What the law derived, kept alongside what is in force so a builder who has changed something can
## still be told what they changed it FROM. An auto-tune whose baseline disappears the moment you
## touch it has removed the only thing worth knowing.
var derived_kp := Vector3.ZERO
var derived_ki := Vector3.ZERO
var derived_kd := Vector3.ZERO

## A_reference / A_this_build, per axis. The whole law, as a number the panel can show.
var scale := Vector3.ONE
## This build's settled angular acceleration per axis, read from FrameBench and never recomputed.
var plant_alpha := Vector3.ZERO
## The largest kd the fitted board's noise floor will pay for, at D_NOISE_BUDGET.
var kd_ceiling := 0.0
## True when the derived kd was cut to that ceiling on roll or pitch.
var d_limited := false

var build: Build = null
## Axis index -> Vector3(kp, ki, kd) the builder set by hand. Sparse, and for the same reason
## AssemblyTweaks' overrides are: an absent axis means "whatever the aircraft implies", which is
## what lets the baseline follow the parts instead of freezing at the first build it saw.
var _overrides: Dictionary = {}

## The reference build's plant, computed once. Three FrameBench spool-ups is not much, but it is the
## divisor in every derivation and it cannot change within a session — the reference build is a
## fixed selection from a read-only catalog.
static var _reference_alpha := Vector3.ZERO


# ---------------------------------------------------------------------------
# Deriving
# ---------------------------------------------------------------------------

static func derive(p_build: Build) -> RateTune:
	var tune := RateTune.new()
	tune.build = p_build
	tune.plant_alpha = plant_alpha_for(p_build)
	tune.kd_ceiling = kd_ceiling_for(p_build)

	var anchor := reference_alpha()
	for axis in 3:
		# A build that cannot produce torque on an axis at all has no plant to scale against, and
		# dividing by it would hand the loop an infinity. It keeps the reference gains, which are
		# as meaningful as anything else on an aircraft that cannot rotate — and Build.warnings()
		# has already said it will not leave the ground.
		tune.scale[axis] = anchor[axis] / tune.plant_alpha[axis] if tune.plant_alpha[axis] > 0.0 else 1.0

	tune.derived_kp = RateModeController.REFERENCE_KP * tune.scale
	tune.derived_ki = RateModeController.REFERENCE_KI * tune.scale
	tune.derived_kd = RateModeController.REFERENCE_KD * tune.scale

	# The ceiling applies to what the law derived, not to what a builder typed: an override is the
	# builder overruling the derivation, and this bound is part of the derivation. They are told
	# what it costs (see warnings()) rather than prevented.
	for axis in 3:
		if tune.derived_kd[axis] > tune.kd_ceiling:
			tune.derived_kd[axis] = tune.kd_ceiling
			tune.d_limited = true

	tune._apply()
	return tune


## The plant gain, per axis: the settled angular acceleration a full command buys, in rad/s^2.
##
## READ FROM THE FRAME BENCH, never re-derived. The bench already computes exactly this, per axis,
## on a scratch powertrain at the nominal-voltage datum and the hover throttle that datum implies —
## the same datum every other spec-sheet figure in this project is quoted at — and its own comments
## explain at length why it is the SETTLED figure rather than a peak read off a visible run. A
## second derivation here would agree for a long time and then stop, which is the divergence this
## project keeps having to undo.
static func plant_alpha_for(p_build: Build) -> Vector3:
	var out := Vector3.ZERO
	for axis in 3:
		var bench := FrameBench.for_build(p_build)
		bench.begin(axis, p_build.hover_throttle())
		out[axis] = bench.peak_alpha_rad_s2
	return out


static func reference_alpha() -> Vector3:
	if _reference_alpha == Vector3.ZERO:
		_reference_alpha = plant_alpha_for(ReferenceBuild.build())
	return _reference_alpha


## What fraction of full command, RMS, a D gain of `kd` spends on the fitted board's gyro noise with
## the aircraft perfectly still.
##
##     d_rms = kd * sd(successive-sample step) / (T * MAX_RATE_RAD_S)
##
## The sensor half — the step SD through the board's own PT1 — belongs to Gyro and is asked for
## rather than restated. This half is the controller's: the step is divided by the sample period to
## become a rate of change, and by MAX_RATE_RAD_S because that is the normalisation the whole loop
## works in.
##
## FcDetails' "Noise at the motors" row is this same call. It has to be: that row exists to say what
## a board costs you in usable D, and this function is where "usable" is decided.
static func d_noise_fraction(p_build: Build, p_kd: float) -> float:
	var gyro := p_build.gyro()
	var period := 1.0 / gyro.sample_rate_hz
	return p_kd * gyro.sample_step_noise_rad_s() / (period * RateModeController.MAX_RATE_RAD_S)


## How many sensor samples of vibration to measure the D term against, and where.
##
## AT HOVER, because vibration is not a constant — it sweeps with throttle, so a single figure has
## to name the condition it describes or it means nothing. Hover is the honest datum: it is where
## the aircraft spends its life, and it is the datum every other spec-sheet figure in this project
## is already quoted at (physics.md §5). A ceiling computed at full throttle would bound the tune
## by a condition the aircraft is in for a few seconds a flight; one computed at idle would bound
## it by nothing at all.
##
## Two seconds of samples after a settling window. The signal is periodic and deterministic, so
## this is a measurement rather than an estimate — there is no variance to average down.
const VIBRATION_SETTLE_SAMPLES := 400
const VIBRATION_WINDOW_SAMPLES := 2000

## The standard deviation of the difference between successive gyro readings caused by VIBRATION
## alone, at hover, rad/s — the vibration counterpart of Gyro.sample_step_noise_rad_s().
##
## MEASURED BY RUNNING THE MODEL, not by an analytic formula, and the reason is the fold-down.
## The signal is a sum of tones whose step statistics are individually elementary, but at hover on
## a 1 kHz sensor the blade-pass line may sit above Nyquist and alias, and an analytic expression
## would have to reproduce that by hand — which is to say it would have to re-derive the sampler
## Gyro already is. Running the real Gyro with the real model for two seconds costs a few thousand
## sines once per tune derivation, against three FrameBench spool-ups this function already sits
## beside, and it cannot disagree with what the aircraft will actually do.
##
## The worst of roll and pitch rather than an average of three: D runs on those two axes (yaw's kd
## is zero on physical grounds), and a bound is about the worse case, not the typical one.
static func vibration_step_noise_rad_s(p_build: Build) -> float:
	var gyro := p_build.gyro()
	if not gyro.vibration is VibrationModel:
		return 0.0

	# The sensor is asked about vibration and nothing else, so bias and white noise are stripped:
	# the board's own contribution is already counted by d_noise_fraction, and counting it twice
	# would be a bound tightening itself.
	gyro.noise_rad_s = 0.0
	gyro.bias_rad_s = Vector3.ZERO

	var hover_rpm := p_build.rpm_at_throttle(p_build.hover_throttle())
	# MotorLayout.MOTOR_NAMES order — set_rpm takes the typed array, not a dict.
	var rpms := PackedFloat64Array()
	for name in MotorLayout.MOTOR_NAMES:
		rpms.append(hover_rpm)
	gyro.vibration.set_rpm(rpms)

	var dt := 1.0 / gyro.sample_rate_hz
	for i in VIBRATION_SETTLE_SAMPLES:
		gyro.update(Vector3.ZERO, dt)

	var previous := gyro.rate_rad_s
	var sum_x := 0.0
	var sum_z := 0.0
	for i in VIBRATION_WINDOW_SAMPLES:
		var reading := gyro.update(Vector3.ZERO, dt)
		var step := reading - previous
		previous = reading
		sum_x += step.x * step.x
		sum_z += step.z * step.z
	var n := float(VIBRATION_WINDOW_SAMPLES)
	return maxf(sqrt(sum_x / n), sqrt(sum_z / n))


## What fraction of full command, RMS, a D gain of `kd` spends on VIBRATION at hover. Same
## arithmetic as d_noise_fraction, on the other half of what the sensor reads.
static func vibration_noise_fraction(p_build: Build, p_kd: float) -> float:
	var gyro := p_build.gyro()
	return noise_fraction_for(vibration_step_noise_rad_s(p_build), gyro.sample_rate_hz, p_kd)


## The arithmetic above, separated from where the noise figure came from (LTHL-20).
##
## D differentiates: it multiplies the CHANGE between successive readings by kd and divides by
## the sample period, so a step of `p_step_noise_rad_s` on a sensor sampled every `period`
## seconds asks the motors for `kd * step / period` rad/s of correction. Over MAX_RATE_RAD_S that
## is a fraction of full stick, and the fraction is what a builder can judge.
##
## EXTRACTED RATHER THAN COPIED INTO STUDIO, and that is the whole point of it existing. Studio
## has something this file cannot get: the step noise a real flight actually produced, measured
## from the gap between the gyro and omega columns, instead of the modelled figure
## vibration_step_noise_rad_s derives by running the sensor at hover. Two numbers, one law — and
## a Studio that spelled the law out again would be the second implementation logs.md exists to
## refuse, in the one place where it would look like reasonable UI code.
##
## What Studio measures is NOT the same quantity, and the pane says so: the log's gyro-minus-omega
## carries the board's white noise and bias as well as vibration, which this function's caller
## above deliberately strips. The measured figure is therefore the whole sensor path, an upper
## bound on the vibration part. It is also the one that actually reached the motors.
static func noise_fraction_for(p_step_noise_rad_s: float, p_sample_rate_hz: float,
		p_kd: float) -> float:
	if p_sample_rate_hz <= 0.0:
		return 0.0
	var period := 1.0 / p_sample_rate_hz
	return p_kd * p_step_noise_rad_s / (period * RateModeController.MAX_RATE_RAD_S)


## The largest kd the fitted board can carry inside D_NOISE_BUDGET — the above, inverted. A board
## with no noise at all has no ceiling, which is INF rather than a large number, because a large
## number would be a bound somebody could later mistake for a measurement.
##
## ---------------------------------------------------------------------------
## WHY VIBRATION IS MEASURED ABOVE AND DELIBERATELY NOT APPLIED HERE
## ---------------------------------------------------------------------------
##
## On a real quad, vibration rather than the board's thermal floor is what caps D, and it is far
## larger. That is not in dispute, it is why vibration_noise_fraction exists, and folding it into
## this ceiling is a two-line change that was written, measured and then deliberately backed out.
## What the measurement showed is why.
##
## Across the catalog with everything but the frame held fixed, the vibration term at the reference
## D gain runs from 0.18% on the 10" to 14.56% on the iFlight Evoque F5 V3, and SIX OF FOURTEEN
## frames blow the 2% budget. The ordering is not arbitrary — it is how close each frame's hover
## rotation frequency sits to its own bending mode, which is exactly the physics this slice set out
## to model, and the Evoque lands at r = 0.99. Applied here, that would cut its D by a factor of
## seven and take its pitch overshoot from 3.8% to 29.7%.
##
## The problem is what decides that ordering. Every frame's mode is anchored on ONE GUESSED NUMBER,
## VibrationModel.REFERENCE_RESONANCE_HZ, for which no source exists and none can be obtained: no
## manufacturer publishes a frame resonance. So applying it here would let a guess set the D gain
## of six named products a builder can go and buy.
##
## And the anchor is not comfortably clear even of the reference build. At 180 Hz the reference
## sits at 1.71% against the 2% budget — 15% of headroom, where the board alone left 4x. Guess
## 160 Hz instead, which is no less defensible, and the reference build itself becomes D-limited,
## the hand-tuned anchor at the top of this file moves, and every flight test in this repo that
## encodes the current tune changes with it. A tune anchor whose position depends on an unsourced
## constant to within 12% is not an anchor.
##
## So the mechanism ships, measured and reportable — an FC bench may show what a build's vibration
## costs in D, and the ranking between builds is trustworthy even though the absolute figure is
## not. What does not ship is letting it move the gains. Two real mechanisms beat three with one
## invented, and this is the same judgement one file over from ThrustValidation's: the bound waits
## for the data rather than the data being assumed to fit the bound.
##
## WHAT WOULD CHANGE THIS: a measured resonance for one real frame. One would do. The scaling law
## carries it to the rest of the catalog, and this function's last line becomes the RMS sum that is
## already written out in vibration_noise_fraction's units.
##
## THAT MEASUREMENT WAS ATTEMPTED (LTHL-18) AND DID NOT SUCCEED, so this function is unchanged and
## the reason is worth knowing before anyone tries again. The instrument exists and works —
## tools/resonance_analysis.py, validated on synthetic modes to within 0.6% and end-to-end through
## a Lothal sweep to +2.8% — and the bound was pre-registered at 25% before any data was read. What
## could not be found was an admissible log. Public blackbox logs fail on one of two things: the
## airframe is not named specifically enough to get an arm length from, or the flight is normal
## flying, in which the 1x line moves 155-235 Hz WITHIN one analysis frame and no peak survives.
## Both walls, and the five criteria a usable log has to meet, are written up in
## landingpage/docs/lothal/validation.md 9.1.
static func kd_ceiling_for(p_build: Build) -> float:
	var per_unit_kd := d_noise_fraction(p_build, 1.0)
	if per_unit_kd <= 0.0:
		return INF
	return D_NOISE_BUDGET / per_unit_kd


# ---------------------------------------------------------------------------
# The builder's own gains
# ---------------------------------------------------------------------------

## Records a hand-set gain triple for one axis. Stored UNCLAMPED and unchecked, exactly as an
## assembly tweak is: tuning is what FPV builders do, Lab warns and never blocks (parts.md), and a
## panel that silently rewrote the number typed into it would be the same mistake in a new place.
func set_gains(axis: int, gains: Vector3) -> void:
	if axis < 0 or axis > 2:
		push_error("unknown rate axis: %d" % axis)
		return
	_overrides[axis] = gains
	_apply()


func clear_override(axis: int) -> void:
	_overrides.erase(axis)
	_apply()


func clear_all() -> void:
	_overrides.clear()
	_apply()


func is_overridden(axis: int) -> bool:
	return _overrides.has(axis)


func has_overrides() -> bool:
	return not _overrides.is_empty()


## The gains in force: the derived tune, with any axis the builder has set replacing it wholesale.
## Wholesale rather than per-gain, because P, I and D on one axis are one decision — a builder who
## raises P and leaves a derived D beside it has a tune neither the law nor they chose.
func _apply() -> void:
	kp = derived_kp
	ki = derived_ki
	kd = derived_kd
	for axis in _overrides:
		var gains: Vector3 = _overrides[axis]
		kp[axis] = gains.x
		ki[axis] = gains.y
		kd[axis] = gains.z


func gains_for(axis: int) -> Vector3:
	return Vector3(kp[axis], ki[axis], kd[axis])


func derived_gains_for(axis: int) -> Vector3:
	return Vector3(derived_kp[axis], derived_ki[axis], derived_kd[axis])


# ---------------------------------------------------------------------------
# What is worth saying about this tune
# ---------------------------------------------------------------------------

## Warn, never block. Two things get said, in the shared severity vocabulary (build_warning.gd):
## the board bounding D is `limiting`, because something binds and the builder should be told WHICH
## PART; a hand tune is `characteristic`, because it is a description of what this aircraft is and
## not an error.
func warnings() -> Array[BuildWarning]:
	var out: Array[BuildWarning] = []

	if d_limited:
		out.append(BuildWarning.limiting(&"d_noise_ceiling",
			"The %s's gyro noise caps D at %.3f — this airframe's plant asks for %.3f. Above the cap the D term spends more than %.0f%% of full command chasing sensor noise into the motors." % [
				build.fc.get("name", "flight controller"), kd_ceiling,
				RateModeController.REFERENCE_KD.x * scale.x, D_NOISE_BUDGET * 100.0],
			{"kd_ceiling": kd_ceiling, "kd_wanted": RateModeController.REFERENCE_KD.x * scale.x,
				"budget_fraction": D_NOISE_BUDGET, "board": str(build.fc.get("name", ""))}))

	if has_overrides():
		var axes: Array[String] = []
		for axis in [0, 1, 2]:
			if _overrides.has(axis):
				axes.append("%s P %.2f I %.3f D %.4f" % [AXIS_NAMES[axis],
					kp[axis], ki[axis], kd[axis]])
		out.append(BuildWarning.characteristic(&"tune_override",
			"Hand-tuned: %s. The derived tune for this aircraft is %s." % [
				", ".join(axes),
				"P %.2f I %.3f D %.4f / yaw P %.2f" % [
					derived_kp.x, derived_ki.x, derived_kd.x, derived_kp.z]],
			{"overridden_axes": _overrides.keys()}))

	return out


## The closed-loop time constant this tune produces, per axis, in seconds — the quantity the law
## holds constant, so the panel can show that it did. MAX_RATE_RAD_S / (A * kp).
func time_constant_s() -> Vector3:
	var out := Vector3.ZERO
	for axis in 3:
		var loop_gain: float = plant_alpha[axis] * kp[axis]
		out[axis] = RateModeController.MAX_RATE_RAD_S / loop_gain if loop_gain > 0.0 else INF
	return out


# ---------------------------------------------------------------------------
# Persistence, as a plain dictionary. The file rules live with PidTunes.
# ---------------------------------------------------------------------------

## Only the axes the builder actually set — sparse, so an absent axis means "whatever the aircraft
## implies" and the baseline keeps following the parts.
func overrides_as_dictionary() -> Dictionary:
	var out: Dictionary = {}
	for axis in _overrides:
		var gains: Vector3 = _overrides[axis]
		out[AXIS_NAMES[axis]] = {"p": gains.x, "i": gains.y, "d": gains.z}
	return out


## A value of the wrong shape is treated as absent rather than coerced, for the same reason
## AssemblyTweaks does it: float("fast") is 0.0, and a silent zero gain is indistinguishable from a
## deliberate one — except that one of them is an aircraft with no control loop on an axis.
func adopt_overrides(stored: Dictionary) -> void:
	_overrides.clear()
	for axis in 3:
		var entry: Variant = stored.get(AXIS_NAMES[axis], null)
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry
		if not (_is_number(row.get("p")) and _is_number(row.get("i")) and _is_number(row.get("d"))):
			push_warning("saved tune: %s is not three numbers; using the derived gains" % AXIS_NAMES[axis])
			continue
		_overrides[axis] = Vector3(float(row["p"]), float(row["i"]), float(row["d"]))
	_apply()


static func _is_number(value: Variant) -> bool:
	return value is float or value is int
