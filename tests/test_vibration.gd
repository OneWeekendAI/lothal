class_name TestVibration
extends RefCounted
## What the airframe shakes the gyro with (LTHL-15). tests/test_gyro.gd already checked that a
## vibration source reaches the reading correctly; this suite checks that the signal is the
## right SHAPE, which is a wholly separate way to be wrong.
##
## ## Why none of these assert "there is more noise with vibration on"
##
## Because that check passes for a model that adds any constant whatsoever, and a constant is
## exactly what white noise already was. The entire point of this slice is that the disturbance
## is STRUCTURED, RPM-DEPENDENT and CONCENTRATED IN NARROW BANDS, so every assertion below is
## about frequency content and how it moves:
##
##   * the 1x line lands where rpm/60 says, and MOVES when the throttle moves;
##   * the blade-pass line lands where blades x rpm/60 says, and is a separate line rather than
##     a louder version of the first — winding the prop imbalance up moves one and not the other;
##   * off resonance the amplitude follows rpm^2, which is the imbalance forcing law;
##   * on resonance it is amplified by the frame mode's own Q, and by that figure specifically;
##   * the frame mode itself moves with arm length and tip mass, by the documented power law.
##
## Every one of those rejects the stub this suite was written against, which was a fixed 200 Hz
## tone at a fixed amplitude. A hollow stub returning zero would have rejected nothing — it
## would have failed every check for the one reason that proves nothing, so the stub was made
## deliberately WRONG rather than deliberately EMPTY.
##
## ## The one thing this suite does not do
##
## It does not compare anything to a measurement, because there is nothing to compare to. See
## VibrationModel's header: no manufacturer publishes frame resonance, modal damping, or prop
## imbalance, so this is a characteristic model and every check here is an internal-consistency
## check. That is a weaker claim than tests/test_build_validation.gd makes and it is stated as
## one, here, rather than left for a reader to infer from the absence of an error bar.

const FS := 1000.0
## A whole number of cycles of every frequency these tests look at, at FS.
const WINDOW := 2000


## One DFT bin of a sampled trace, by correlation. TestGyro's, deliberately reached for rather
## than copied: the two suites measuring the amplitude of a tone by two slightly different
## expressions is how they come to disagree about the same signal.
static func _amplitude_at(samples: PackedFloat64Array, hz: float) -> float:
	return TestGyro._amplitude_at(samples, hz, FS)


## Runs a vibration model through a real Gyro at a fixed set of motor RPMs and returns the roll
## axis (body X) trace, in rad/s.
##
## Through a Gyro rather than by calling the model directly, on purpose: what any consumer ever
## sees is the signal AFTER the sensor's sample-and-hold and PT1, and a suite that measured the
## model's own output would be checking a signal nobody receives. The cutoff is opened up to
## 2 kHz for most checks so the filter's own rolloff does not have to be divided out of every
## number; the checks that care about the filter say so.
static func _trace(model: VibrationModel, rpms: Array, count: int = WINDOW,
		cutoff_hz: float = 2000.0) -> PackedFloat64Array:
	var gyro := Gyro.new(FS, cutoff_hz, 0.0, Vector3.ZERO)
	gyro.vibration = model
	model.set_rpm(PackedFloat64Array([rpms[0], rpms[1], rpms[2], rpms[3]]))
	var out := PackedFloat64Array()
	# A few hundred samples of settling before measuring, so the PT1's step response is not
	# folded into the amplitude of the tone it is passing.
	for i in 400:
		gyro.update(Vector3.ZERO, 1.0 / FS)
	for i in count:
		out.append(gyro.update(Vector3.ZERO, 1.0 / FS).x)
	return out


static func _all(rpm: float) -> Array:
	return [rpm, rpm, rpm, rpm]


## The largest angular rate VIBRATION ALONE contributes to the gyro on a real aircraft held at a
## fixed throttle, in rad/s. Two identical cores are flown side by side with identical commands,
## one with its vibration source removed, and the readings are subtracted — so the board's bias,
## its seeded white noise and the filter's lag all cancel exactly rather than being estimated and
## subtracted approximately.
static func _flown_shake(throttle: float) -> float:
	var shaken := ReferenceBuild.build_drone_core()
	var still := ReferenceBuild.build_drone_core()
	still.gyro.vibration = null
	shaken.prime_motors(throttle)
	still.prime_motors(throttle)
	var cmd := MotorMixer.mix(throttle, 0.0, 0.0, 0.0)
	var worst := 0.0
	for i in 1000:
		shaken.step(cmd, 1.0 / FS)
		still.step(cmd, 1.0 / FS)
		if i >= 400:
			worst = maxf(worst, (shaken.observables.gyro_rad_s - still.observables.gyro_rad_s).length())
	return worst


static func run() -> Array:
	var results: Array = []
	var build := ReferenceBuild.build()
	var blades: float = build.prop_geometry().blades

	# -----------------------------------------------------------------------
	# The 1x line is at rotation frequency, and it MOVES
	# -----------------------------------------------------------------------
	# Two rpms, chosen so both fundamentals and both blade-pass lines sit below Nyquist and on
	# exact DFT bins of the window. The stub fails this outright: its tone does not move.
	var low_rpm := 6000.0    # 100 Hz rotation, 300 Hz blade pass
	var high_rpm := 9000.0   # 150 Hz rotation, 450 Hz blade pass

	var quiet_model := VibrationModel.for_build(build)
	quiet_model.imbalance_kg = 0.0005   # wound up, so the 1x line is unambiguous
	var low_trace := _trace(quiet_model, _all(low_rpm))
	var low_at_100 := _amplitude_at(low_trace, 100.0)
	var low_at_150 := _amplitude_at(low_trace, 150.0)

	var moved_model := VibrationModel.for_build(build)
	moved_model.imbalance_kg = 0.0005
	var high_trace := _trace(moved_model, _all(high_rpm))
	var high_at_100 := _amplitude_at(high_trace, 100.0)
	var high_at_150 := _amplitude_at(high_trace, 150.0)

	results.append(TestResult.new(
		"the imbalance line sits at rotation frequency and moves with the throttle",
		low_at_100 > low_at_150 * 8.0 and high_at_150 > high_at_100 * 8.0,
		"at %.0f rpm: %.4f rad/s in the 100 Hz bin vs %.4f at 150; at %.0f rpm: %.4f at 100 vs %.4f at 150"
			% [low_rpm, low_at_100, low_at_150, high_rpm, high_at_100, high_at_150]))

	# -----------------------------------------------------------------------
	# Blade passage is a SECOND line, at blades x rotation
	# -----------------------------------------------------------------------
	var bp_hz := blades * high_rpm / 60.0
	var bp_amp := _amplitude_at(high_trace, bp_hz)
	results.append(TestResult.new(
		"blade passage is present at blades x rotation, where the arithmetic says",
		bp_amp > 1e-4 and _amplitude_at(high_trace, bp_hz + 50.0) < bp_amp * 0.2,
		"%.0f rpm on a %d-blade prop: %.5f rad/s at %.0f Hz, %.5f rad/s 50 Hz away"
			% [high_rpm, int(blades), bp_amp, bp_hz, _amplitude_at(high_trace, bp_hz + 50.0)]))

	# ...and it is a DIFFERENT mechanism, not a louder copy of the first. Prop imbalance is a
	# build-quality property; blade passage is aerodynamic and present on a perfectly balanced
	# prop. Winding one up must move one line and leave the other where it was. A lumped model
	# with a single amplitude passes every check above this one and fails this one, which is
	# why it is here.
	var chipped := VibrationModel.for_build(build)
	chipped.imbalance_kg = quiet_model.imbalance_kg * 4.0
	var chipped_trace := _trace(chipped, _all(high_rpm))
	var chipped_1x := _amplitude_at(chipped_trace, 150.0)
	var chipped_bp := _amplitude_at(chipped_trace, bp_hz)
	results.append(TestResult.new(
		"prop imbalance and blade passage are separate mechanisms: winding one up moves one line",
		chipped_1x > high_at_150 * 3.5 and absf(chipped_bp - bp_amp) < bp_amp * 0.02,
		"4x the imbalance: the 1x line goes %.4f -> %.4f rad/s while blade pass holds %.5f -> %.5f"
			% [high_at_150, chipped_1x, bp_amp, chipped_bp]))

	# -----------------------------------------------------------------------
	# Off resonance, the imbalance forcing follows rpm^2
	# -----------------------------------------------------------------------
	# m * r * omega^2 is the whole of it, and it is the reason a prop nick that is unnoticeable
	# at idle is a motor-melting resonance at full throttle. Measured well below the frame mode
	# so the amplification below is not folded into the ratio, and divided out of it explicitly
	# rather than assumed negligible.
	var square_model := VibrationModel.for_build(build)
	square_model.imbalance_kg = 0.0005
	var a_rpm := 2400.0   # 40 Hz
	var b_rpm := 4800.0   # 80 Hz
	var a_amp := _amplitude_at(_trace(square_model, _all(a_rpm)), a_rpm / 60.0)
	var square_b := VibrationModel.for_build(build)
	square_b.imbalance_kg = 0.0005
	var b_amp := _amplitude_at(_trace(square_b, _all(b_rpm)), b_rpm / 60.0)
	# The frame mode amplifies both, unequally, so the expected ratio is 4 times the ratio of
	# the two modal gains rather than 4 flat.
	var modal_a := VibrationModel.modal_gain(a_rpm / 60.0, square_model.resonance_hz, square_model.damping_ratio)
	var modal_b := VibrationModel.modal_gain(b_rpm / 60.0, square_model.resonance_hz, square_model.damping_ratio)
	var expected := 4.0 * modal_b / modal_a
	results.append(TestResult.new(
		"imbalance forcing goes as rpm^2 — doubling the rpm quadruples it, less the modal gain",
		absf(b_amp / a_amp - expected) < expected * 0.05,
		"%.0f -> %.0f rpm: %.5f -> %.5f rad/s, a factor of %.2f against the predicted %.2f"
			% [a_rpm, b_rpm, a_amp, b_amp, b_amp / a_amp, expected]))

	# -----------------------------------------------------------------------
	# The frame mode, and the sweep through it
	# -----------------------------------------------------------------------
	# This is the landmark the FC bench exists for. Put the 1x line ON the frame mode and it is
	# amplified by the mode's own Q; move it off and the amplification goes away. A model with
	# no resonance in it passes everything above and fails here.
	var res_model := VibrationModel.for_build(build)
	res_model.imbalance_kg = 0.0005
	var on_rpm := res_model.resonance_hz * 60.0
	var off_rpm := on_rpm * 0.5
	var on_amp := _amplitude_at(_trace(res_model, _all(on_rpm)), on_rpm / 60.0)
	var off_model := VibrationModel.for_build(build)
	off_model.imbalance_kg = 0.0005
	var off_amp := _amplitude_at(_trace(off_model, _all(off_rpm)), off_rpm / 60.0)
	# Forcing alone would put the on-resonance line at 4x the off-resonance one (rpm^2 across a
	# factor of two). Anything beyond that is the mode. Q = 1/(2*zeta) at resonance exactly.
	var q := 1.0 / (2.0 * res_model.damping_ratio)
	var amplification := (on_amp / off_amp) / 4.0 * VibrationModel.modal_gain(off_rpm / 60.0,
		res_model.resonance_hz, res_model.damping_ratio)
	results.append(TestResult.new(
		"a harmonic landing on the frame mode is amplified by the mode's own Q",
		absf(amplification - q) < q * 0.05,
		"1x swept onto the %.0f Hz mode: amplification %.1fx against Q = 1/(2*zeta) = %.1f at zeta %.3f"
			% [res_model.resonance_hz, amplification, q, res_model.damping_ratio]))

	# -----------------------------------------------------------------------
	# The mode is a property of the AIRFRAME, by a stated law
	# -----------------------------------------------------------------------
	# f goes as L^-1.5 for a tip-mass-dominated cantilever (see VibrationModel.resonance_hz_for).
	# Asserting the exponent rather than "the whoop's is higher" is what makes this a check on a
	# documented derivation instead of on a hunch — and thirteen hand-authored resonance_hz specs
	# in frames.json would have passed the hunch version while meaning nothing.
	var catalog := PartsCatalog.load_default()
	var whoop := Build.from_ids(catalog, "frame_65mm_whoop", ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)
	var big := Build.from_ids(catalog, "frame_10in_long_range", ReferenceBuild.MOTOR_ID,
		ReferenceBuild.PROPELLER_ID, ReferenceBuild.BATTERY_ID, ReferenceBuild.ESC_ID,
		ReferenceBuild.FC_ID)
	# Same motor and prop on both, so tip mass is held and arm length is the only thing moving.
	var f_whoop := VibrationModel.for_build(whoop).resonance_hz
	var f_big := VibrationModel.for_build(big).resonance_hz
	var predicted_ratio := pow(big.arm_m / whoop.arm_m, VibrationModel.ARM_LENGTH_EXPONENT)
	results.append(TestResult.new(
		"the frame mode follows arm length by the cantilever law, not by an authored constant",
		absf((f_whoop / f_big) / predicted_ratio - 1.0) < 0.001,
		"%.0f mm arm: %.0f Hz; %.0f mm arm: %.0f Hz; ratio %.2f against L^%.1f = %.2f"
			% [whoop.arm_m * 1000.0, f_whoop, big.arm_m * 1000.0, f_big,
				f_whoop / f_big, VibrationModel.ARM_LENGTH_EXPONENT, predicted_ratio]))

	# ...and with tip mass, by the other half of the same formula. A heavier motor lowers the
	# mode, which is why the same frame rings differently once you rebuild it.
	var heavy := VibrationModel.resonance_hz_for(build.arm_m, 0.0365 * 4.0)
	var light := VibrationModel.resonance_hz_for(build.arm_m, 0.0365)
	results.append(TestResult.new(
		"a heavier motor and prop lower the frame mode, as sqrt of the tip mass",
		absf(light / heavy - 2.0) < 0.001,
		"36.5 g at the tip: %.0f Hz; 146.0 g: %.0f Hz; ratio %.3f against sqrt(4) = 2"
			% [light, heavy, light / heavy]))

	# -----------------------------------------------------------------------
	# The soft mount has a consequence
	# -----------------------------------------------------------------------
	# It was decoration until there was something to isolate. Above the mount's own natural
	# frequency it attenuates; BELOW it, it amplifies, which is real and is the reason a soft
	# mount is not a free win. Both directions are asserted, because a model that only ever
	# reduced the number would be an attenuator wearing an isolator's name.
	var bare := VibrationModel.for_build(build)
	bare.imbalance_kg = 0.0005
	var padded := VibrationModel.for_build(build)
	padded.imbalance_kg = 0.0005
	padded.soft_mount_m = 0.002
	var fast_rpm := 18000.0    # 300 Hz, well above the padded mount's natural frequency
	var isolated := _amplitude_at(_trace(padded, _all(fast_rpm)), fast_rpm / 60.0)
	var unisolated := _amplitude_at(_trace(bare, _all(fast_rpm)), fast_rpm / 60.0)
	var mount_hz := padded.mount_hz()
	results.append(TestResult.new(
		"a soft mount isolates above its own natural frequency, so the pad is no longer decoration",
		isolated < unisolated * 0.6,
		"%.0f rpm (%.0f Hz) against a %.0f Hz mount: %.5f rad/s padded vs %.5f bare (%.2fx)"
			% [fast_rpm, fast_rpm / 60.0, mount_hz, isolated, unisolated, isolated / unisolated]))

	var at_mount_rpm := mount_hz * 60.0
	var amplified := _amplitude_at(_trace(padded, _all(at_mount_rpm)), mount_hz)
	var unamplified := _amplitude_at(_trace(bare, _all(at_mount_rpm)), mount_hz)
	results.append(TestResult.new(
		"...and AMPLIFIES at its own natural frequency — a soft mount is not a free win",
		amplified > unamplified * 1.5,
		"a harmonic sitting on the %.0f Hz mount: %.5f rad/s padded vs %.5f bare (%.2fx)"
			% [mount_hz, amplified, unamplified, amplified / unamplified]))

	# -----------------------------------------------------------------------
	# The defaults are quiet, and the model is deterministic
	# -----------------------------------------------------------------------
	# The DEFAULT_NOISE_RAD_S precedent (gyro.gd): the default must fly clean, and winding it up
	# is how the builder learns what it does. If this figure had to be raised to be interesting,
	# the number would be wrong rather than the test.
	var stock := VibrationModel.for_build(build)
	var hover_rpm := build.rpm_at_throttle(build.hover_throttle())
	var stock_trace := _trace(stock, _all(hover_rpm), WINDOW, Gyro.DEFAULT_CUTOFF_HZ)
	var worst := 0.0
	for v in stock_trace:
		worst = maxf(worst, absf(v))
	results.append(TestResult.new(
		"a decently balanced reference build shakes its gyro by under 1 deg/s at hover",
		worst < deg_to_rad(1.0),
		"%.0f rpm at hover: peak %.3f deg/s through the stock %.0f Hz cutoff, at the default %.3f g offset"
			% [hover_rpm, rad_to_deg(worst), Gyro.DEFAULT_CUTOFF_HZ,
				VibrationModel.DEFAULT_IMBALANCE_KG * 1000.0]))

	# Deterministic and phase-locked: no RNG anywhere in this model, so two identically
	# configured aircraft shake identically and a respawn replays the same shake. gyro.gd's
	# "the same flight twice" guarantee has to survive this slice.
	var det_a := VibrationModel.for_build(build)
	var det_b := VibrationModel.for_build(build)
	var trace_a := _trace(det_a, _all(hover_rpm), 500)
	var trace_b := _trace(det_b, _all(hover_rpm), 500)
	var identical := true
	for i in trace_a.size():
		if trace_a[i] != trace_b[i]:
			identical = false
			break
	results.append(TestResult.new(
		"the vibration model is deterministic — two identical aircraft shake identically",
		identical,
		"500 samples compared, traces %s" % ("identical" if identical else "DIVERGED")))

	# -----------------------------------------------------------------------
	# It is the AIRCRAFT's vibration, and the aircraft pushes its own rpm in
	# -----------------------------------------------------------------------
	# Every check above drives the model by hand. This one flies a real DroneCore and asks
	# whether the gyro's reading follows the motors — which is the difference between a model
	# that exists and a model that is connected. It fails on a core that builds a bare Gyro,
	# and it fails on a core that fits the model but never tells it what the motors are doing.
	var core := ReferenceBuild.build_drone_core()
	results.append(TestResult.new(
		"a built aircraft fits its own vibration model — the shake follows the parts",
		core.gyro.vibration is VibrationModel,
		"DroneCore.gyro.vibration is %s" % ("a VibrationModel" if core.gyro.vibration is VibrationModel else "absent"))
	)

	# ...and the core keeps it fed. A model fitted but never told what the motors are doing sits
	# at zero rpm for ever and contributes nothing, which is a live failure mode: the wiring is
	# two lines in two files and only one of them is visible from the type above.
	#
	# Measured as the DIFFERENCE between two otherwise identical aircraft, one with the vibration
	# source removed. Reading "sensor minus truth" instead would fold in the board's bias, its
	# white noise and the PT1's own lag — three things that are present at zero throttle too, and
	# that between them are larger than the quantity under test at hover. Differencing two runs
	# that share a seed cancels all three exactly, and leaves only the shake.
	var idle_shake := _flown_shake(0.0)
	var hover_shake := _flown_shake(ReferenceBuild.hover_throttle())
	results.append(TestResult.new(
		"the core feeds the model its motor speeds: dead motors shake the sensor, spinning ones shake it far more",
		hover_shake > idle_shake * 20.0 and idle_shake < 1e-9,
		"vibration's own contribution peaks at %.5f deg/s with the motors stopped and %.5f deg/s at hover"
			% [rad_to_deg(idle_shake), rad_to_deg(hover_shake)]))

	# -----------------------------------------------------------------------
	# The garage's knob reaches the physics
	# -----------------------------------------------------------------------
	# Prop imbalance is a build-quality property, so it lives as an assembly tweak rather than as
	# a spec on prop_5x43x3 — and a tweak that does not reach the sensor is the same decoration
	# the soft-mount pad was before this slice. The whole path is exercised: the slider's value,
	# through AssemblyTweaks.resolved_m, into Build's assembly dictionary, into VibrationModel,
	# out of a Gyro. Any link dropped and the two readings are identical.
	var tweaks := AssemblyTweaks.new()
	var tweaked := ReferenceBuild.build()
	tweaks.set_mm(AssemblyTweaks.PROP_IMBALANCE, 0.4)
	tweaked.set_assembly(tweaks.resolved_m(tweaked))
	var stock_build := ReferenceBuild.build()
	var rough := _amplitude_at(_trace(VibrationModel.for_build(tweaked), _all(hover_rpm)), hover_rpm / 60.0)
	var smooth := _amplitude_at(_trace(VibrationModel.for_build(stock_build), _all(hover_rpm)), hover_rpm / 60.0)
	results.append(TestResult.new(
		"the garage's prop-balance slider reaches the gyro, in proportion to what was set",
		absf(rough / smooth - 20.0) < 0.5,
		"0.020 g reads %.4f rad/s at hover and 0.400 g reads %.4f — a factor of %.1f against the 20x set"
			% [smooth, rough, rough / smooth]))

	return results
