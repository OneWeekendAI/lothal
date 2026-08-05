class_name VibrationModel
extends VibrationSource
## What a quadcopter shakes its own gyro with: prop imbalance at rotation frequency, blade
## passage at blades x that, and a frame mode that amplifies whichever harmonic happens to be
## sweeping through it.
##
## White noise was the wrong shape for this. Real gyro noise is structured, rpm-dependent and
## concentrated in narrow bands, and the difference is not cosmetic — it is why a D gain that
## is fine at hover heats motors at half throttle, why a cutoff sweep is worth doing, and why
## soft-mount pads exist. With white noise none of those have a cause.
##
## ===========================================================================
## THIS IS A CHARACTERISTIC MODEL, NOT A PREDICTIVE ONE. READ THIS FIRST.
## ===========================================================================
##
## NO MANUFACTURER PUBLISHES FRAME RESONANCE FREQUENCY, MODAL DAMPING, OR PROP IMBALANCE MASS.
## Not one, for any part in data/parts/. This is a harder sourcing wall than the one that capped
## build validation at two aircraft, and it changes what this file is allowed to claim.
##
## ThrustValidation can quote an error bar because held-out measurements exist: someone put a
## different prop on the same motor and wrote down the thrust. Nothing here can be checked that
## way. There is no held-out frame resonance to be wrong about.
##
## So what this file offers is not accuracy, it is STRUCTURE. Every relationship in it — how the
## amplitude follows rpm, how the mode follows arm length and tip mass, how a resonance amplifies,
## how an isolator transmits — is a law with a derivation, and each of those is stated where it is
## used so it can be argued with. What none of them have is a calibration. The absolute scale rests
## on ONE free constant, SENSOR_RESPONSE_RAD_S_PER_N, and it is a guess.
##
## The consequence, and it is a hard rule: NO BENCH BUILT ON THIS MAY QUOTE AN ERROR BAR.
## labs-and-sim.md §2.1 says a bench that will not quote its own error bar is decoration. The
## converse is worse: a bench quoting a fabricated one is a lie with a number on it. What a
## vibration bench may honestly show is how a peak MOVES with throttle, which is the instructive
## part and needs no absolute scale to be true.
##
## Where a number below has no source, it says so in that voice.
##
## ===========================================================================
## THE THREE MECHANISMS
## ===========================================================================
##
## 1. PROP IMBALANCE, at rotation frequency. An unbalanced prop is a mass offset from the shaft
##    axis, so the forcing is once per revolution and its magnitude is m * r * omega^2 — exact,
##    elementary, and the reason a nick you cannot feel at idle is a catastrophe at full throttle.
##    This is the term with real per-motor rpm behind it: the four motors are NOT at the same rpm
##    while the aircraft is manoeuvring, which is what makes the signal a beating, wandering thing
##    rather than a single sine.
##
## 2. BLADE PASSAGE, at blades x rotation. Aerodynamic — each blade passing the arm sheds a
##    pressure pulse — so it is present on a perfectly balanced prop and cannot be balanced out.
##
## 3. FRAME RESONANCE, a lightly damped mode that amplifies whatever excites it. This is what
##    turns a modest forcing into a D-term problem, and the interesting behaviour is entirely in
##    the interaction: as throttle rises the harmonics sweep UPWARD through a FIXED frame mode, so
##    the gyro sees a peak that arrives, screams and leaves. That sweep is the landmark.
##
## Plus one modifier: a soft-mount pad, which is an isolator and therefore not a free win — see
## mount_hz().
##
## ===========================================================================
## WHAT IS NOT MODELLED
## ===========================================================================
##
## Motor cogging and ESC commutation ripple (electrical, at pole-pairs x rotation — Observables
## already computes that frequency for the audio synthesiser and it would be cheap to add, but it
## is a fourth unsourced amplitude and three is already the limit of what can be defended). Higher
## frame modes; there is exactly one, and real frames have many. Gyroscopic stiffening of the arms
## with rpm. Prop-wash buffeting, which is broadband and would want a different treatment entirely.
## Any coupling back into the rigid body — see vibration_source.gd for why there is none.

# ---------------------------------------------------------------------------
# The frame mode
# ---------------------------------------------------------------------------

## A quad arm is a cantilever with a motor and a prop bolted to its tip, and its first bending
## mode is the textbook Rayleigh result:
##
##     f = (1 / 2pi) * sqrt( 3 EI / ( L^3 * (m_tip + (33/140) * m_arm) ) )
##
## Two things follow, and only the second one needs a number nobody publishes.
##
## THE EXPONENT ON LENGTH IS 1.5, NOT 2. The commonly quoted 1/L^2 law is for a BARE cantilever,
## where the effective mass is the beam's own and therefore itself proportional to L; that L
## cancels one power and leaves L^-2. Here the tip mass dominates and does not scale with L at
## all, so the L^3 in the denominator stands alone and the exponent is 1.5. On the reference build
## the arm's own share — (33/140) x roughly 10 g of arm against 36.5 g of motor and prop — is
## about a 7% correction, so it is dropped, and dropping it is what makes the exponent exactly
## 1.5 rather than something between 1.5 and 2 that varies down the catalog. That approximation
## is the least defensible thing in this block and it is the one worth revisiting first.
##
## THE MASS TERM IS REAL AND IT IS PUBLISHED. Motor mass and prop mass are both in the catalog, so
## a heavier motor genuinely lowers the mode, by sqrt — which is why the same frame rings
## differently once you rebuild it, and it costs nothing to model because the data is already
## there.
##
## WHAT IS NOT PUBLISHED is EI: the bending stiffness of a carbon arm. So the formula is used as a
## SCALING LAW anchored on one guessed frequency rather than evaluated from first principles.
## Thirteen hand-authored resonance_hz fields in frames.json would have been thirteen fabricated
## numbers wearing the catalog's authority; this is one fabricated number and one derivation, and
## the derivation is checkable even though the anchor is not.
const ARM_LENGTH_EXPONENT := 1.5

## THE ANCHOR, AND IT IS A GUESS. The first arm-bending mode of the reference 5" freestyle frame —
## a 110 mm arm carrying a 2207 and a 5x4.3x3, so 36.5 g at the tip.
##
## No source. There is no source. What can be said for it: blackbox spectra from 5" quads put
## frame and arm modes in the low hundreds of hertz, and 180 Hz sits in that band. What it buys is
## a sweep that lands in the interesting place — the reference build's 1x line crosses it at about
## 44% throttle and its blade-pass line crosses it at about 15%, so a builder sweeping the throttle
## meets both peaks in the range they actually fly in. That is a reason to believe the model is
## USEFUL and not a reason to believe it is RIGHT, and the two are being kept apart deliberately.
##
## Everything downstream is a ratio to this. Move it and every frame moves together.
const REFERENCE_RESONANCE_HZ := 180.0
const REFERENCE_ARM_M := 0.110
## 2207 (32 g) plus a 5x4.3x3 (4.5 g), which is what REFERENCE_RESONANCE_HZ is quoted for.
const REFERENCE_TIP_MASS_KG := 0.0365

## Modal damping, as a fraction of critical. GUESSED, but inside a published range rather than out
## of the air: carbon-fibre laminate itself is very lightly damped (loss factors of a fraction of a
## percent, zeta well under 0.01), while BOLTED assemblies — which is what a quad is, arms bolted
## through a plate — are conventionally taken at zeta 0.02 to 0.05 because the joints do most of
## the damping. 0.03 is the middle of that, and it puts Q = 1/(2*zeta) at about 17.
##
## This number decides how sharp the peak is and therefore how dramatic the sweep looks, so it is
## the one most tempting to tune for effect. It has not been.
const DEFAULT_DAMPING_RATIO := 0.03


# ---------------------------------------------------------------------------
# The forcing
# ---------------------------------------------------------------------------

## Residual imbalance mass of one prop, at the blade radius — the aircraft's default build quality.
##
## A BUILD QUALITY PROPERTY, NOT A PART PROPERTY, which is why it is a field here and adjustable
## through AssemblyTweaks rather than a spec on prop_5x43x3. The same prop out of the same bag is
## balanced or not depending on what happened to it, and a catalog entry claiming otherwise would
## be asserting something about an object nobody has measured.
##
## 20 mg is a decently balanced prop: a hobby balancer resolves down to a few milligrams, an
## out-of-the-box prop is typically a few tens, and a prop with a visible nick is hundreds. That
## span is the range the tweak offers.
##
## LOW BY DEFAULT, on the DEFAULT_NOISE_RAD_S precedent (gyro.gd): the stock aircraft must fly
## clean, and winding it up is how a builder learns what it does. At this default the reference
## build shakes its gyro by about half a degree per second at hover, which is below the sensor's
## own noise floor's practical significance and disturbs no existing test.
const DEFAULT_IMBALANCE_KG := 0.00002

## Blade passage, expressed as THE ROTATING IMBALANCE THAT WOULD PRODUCE THE SAME FORCE.
##
## It is not an imbalance — it is aerodynamic, and it acts at blades x rotation, not at rotation.
## But its magnitude scales with disc loading, which at fixed geometry goes as rpm^2, which is the
## same law m * r * omega^2 already expresses. So rather than introduce a SECOND unsourced
## amplitude scale with its own units and its own calibration, it is quoted in the units of the
## first. One free scale constant in this file instead of two, and the conversion is stated rather
## than buried.
##
## 30 mg-equivalent puts blade passage slightly above a well-balanced prop's 1x line, which is what
## makes it the floor a builder cannot balance away — the thing still there after the props are
## perfect. GUESSED, like everything else in this block.
const BLADE_PASS_EQUIVALENT_KG := 0.00003

## THE ONE FREE CONSTANT. How much angular rate the sensor reads per newton of forcing at an arm
## tip, off resonance and with no isolator.
##
## Physically it stands for the airframe's compliance and the modal shape that maps a tip force
## onto rotation at the stack — which is exactly the quantity no data exists for, so rather than
## pretend to derive it, it is set by choosing an OUTCOME: a decently balanced reference build
## should read about half a degree per second at hover, which is roughly what a clean 5" quad's
## blackbox trace shows.
##
## That is circular and it is stated as circular. What it is NOT is arbitrary in its consequences:
## every ratio in this file — between throttles, between frames, between a chipped prop and a good
## one, between a padded motor and a bare one — is set by the laws above and is untouched by this
## number. Change it and every reading scales together. It sets the units of the y-axis and
## nothing else, which is precisely why a bench built on this may show the SHAPE of a sweep and
## must not quote a figure.
const SENSOR_RESPONSE_RAD_S_PER_N := 0.003

## How much of an arm's shaking shows up on the YAW axis rather than on roll and pitch.
##
## An arm bends far more easily than it twists, so most of what the sensor sees is roll and pitch —
## but not all of it, and a model that put nothing on yaw would tell a builder that yaw D is free.
## 0.15 is a guess with no source; its only defence is that it is small and not zero.
const YAW_COUPLING := 0.15

## Four props balanced independently have NO phase relationship, and the model must not accidentally
## assert one. With every motor at the same rpm and the same starting phase, the four arms' roll
## contributions cancel exactly — a silent, physically meaningless null that would have made a
## hovering aircraft the quietest thing in the simulation.
##
## So the four start at fixed, deterministic, mutually irrational-ish offsets (golden-ratio spacing,
## which is the standard trick for "spread out and not commensurate"). Fixed rather than random
## because gyro.gd's "the same flight twice" guarantee is not negotiable and this model contains no
## RNG at all.
const PHASE_OFFSETS := [0.0, 3.883222, 7.766444, 11.649666]


# ---------------------------------------------------------------------------
# The soft mount
# ---------------------------------------------------------------------------

## The natural frequency of a 1 mm pad under one motor. GUESSED, and the one below is derived:
## a pad of given material and area has stiffness k = EA/t, so f_n goes as 1/sqrt(thickness) —
## which is grounded, and is why a thicker pad isolates lower.
const MOUNT_REFERENCE_HZ := 250.0
const MOUNT_REFERENCE_THICKNESS_M := 0.001
## Rubber and silicone pads are heavily damped compared to the frame. Guessed, in the usual range.
const MOUNT_DAMPING_RATIO := 0.1


# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

## Per motor, in MotorLayout.MOTOR_NAMES order. Pushed in by DroneCore every step, because the
## four are not equal while the aircraft is manoeuvring and that inequality is the signal.
var rpm := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

var imbalance_kg := DEFAULT_IMBALANCE_KG
var blade_pass_kg := BLADE_PASS_EQUIVALENT_KG
var soft_mount_m := 0.0
var resonance_hz := REFERENCE_RESONANCE_HZ
var damping_ratio := DEFAULT_DAMPING_RATIO
var blades := 3.0
var prop_radius_m := 0.0635

## Body-frame direction each motor's arm-bending shows up along, and the sign its torsion puts on
## yaw. Precomputed from the geometry once, because it is fixed for the airframe and recomputing a
## cross product four times per sample at 1 kHz is the kind of thing that turns a sim into a
## slideshow.
var _axis: Array[Vector3] = []
var _yaw_sign := PackedFloat64Array([1.0, -1.0, -1.0, 1.0])

## Integrated, not computed from t. A signal whose frequency follows rpm cannot be written as
## sin(2*pi*f*t): the moment the throttle moves, f changes and the phase jumps, which would put a
## broadband click into the gyro every time a motor changed speed. Integrating d(phase) = 2*pi*f*dt
## keeps it continuous through any throttle input, which is the whole reason this is a stateful
## object rather than a function of time.
var _phase := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _last_t := 0.0


func _init(p_arm_m: float = REFERENCE_ARM_M) -> void:
	_set_geometry(p_arm_m)


## An aircraft's vibration, from the aircraft. THE ONE PLACE a build becomes a vibration model.
static func for_build(build: Build) -> VibrationModel:
	var model := VibrationModel.new(build.arm_m)
	var geometry := build.prop_geometry()
	model.blades = geometry.blades
	model.prop_radius_m = geometry.diameter_m * 0.5
	model.resonance_hz = resonance_hz_for(build.arm_m, tip_mass_kg_for(build))
	model.soft_mount_m = float(build.assembly_value("soft_mount_m"))
	model.imbalance_kg = float(build.assembly_value("prop_imbalance_g")) / 1000.0
	return model


## What hangs off the end of one arm: the motor and its prop. Both masses are published, which is
## what lets the frame mode depend on the build rather than only on the frame.
static func tip_mass_kg_for(build: Build) -> float:
	return (float(build.motor.get("mass_g", 0.0)) + float(build.propeller.get("mass_g", 0.0))) / 1000.0


## The frame's first arm-bending mode — the scaling law at the top of this file, anchored on
## REFERENCE_RESONANCE_HZ. Static and takes raw numbers so a bench can sweep it without a Build.
static func resonance_hz_for(arm_m: float, tip_mass_kg: float) -> float:
	if arm_m <= 0.0 or tip_mass_kg <= 0.0:
		return REFERENCE_RESONANCE_HZ
	return REFERENCE_RESONANCE_HZ \
		* pow(REFERENCE_ARM_M / arm_m, ARM_LENGTH_EXPONENT) \
		* sqrt(REFERENCE_TIP_MASS_KG / tip_mass_kg)


## A single-degree-of-freedom mode's magnitude response to forcing at `hz`:
##
##     |H(r)| = 1 / sqrt( (1 - r^2)^2 + (2 zeta r)^2 ),   r = f / f_n
##
## Unity well below the mode, 1/(2 zeta) exactly ON it, and falling as 1/r^2 above. The unity at
## DC matters: it means this term AMPLIFIES and never attenuates the forcing, so a build whose
## harmonics all miss the mode reads exactly what the forcing alone would give, and the resonance
## is visible as an addition rather than baked into every number.
static func modal_gain(hz: float, res_hz: float, zeta: float) -> float:
	if res_hz <= 0.0:
		return 1.0
	var r := hz / res_hz
	var real := 1.0 - r * r
	var imag := 2.0 * zeta * r
	return 1.0 / sqrt(real * real + imag * imag)


## The natural frequency of the fitted soft-mount pad, or INF when there is no pad — which makes
## transmissibility exactly 1 below, with no branch for "bare" anywhere else.
##
## f_n goes as 1/sqrt(thickness) because a pad's stiffness is EA/t. That part is grounded; the
## 250 Hz at 1 mm it is anchored on is not.
func mount_hz() -> float:
	if soft_mount_m <= 0.0:
		return INF
	return MOUNT_REFERENCE_HZ * sqrt(MOUNT_REFERENCE_THICKNESS_M / soft_mount_m)


## What fraction of the forcing at `hz` the pad passes through to the frame:
##
##     T(r) = sqrt( (1 + (2 zeta r)^2) / ((1 - r^2)^2 + (2 zeta r)^2) ),   r = f / f_mount
##
## THE PAD IS NOT A FREE WIN, and this formula is why. Below r = sqrt(2) an isolator AMPLIFIES —
## it passes more through than no pad at all, peaking hard at its own natural frequency — and only
## above sqrt(2) does it start to isolate. That is real, it is the reason soft mounts are chosen
## for a frequency rather than for softness, and it is a thing a builder can now discover by
## fitting a pad and watching the wrong harmonic get worse.
func mount_transmissibility(hz: float) -> float:
	var f_n := mount_hz()
	if is_inf(f_n):
		return 1.0
	var r := hz / f_n
	var damped := 2.0 * MOUNT_DAMPING_RATIO * r
	var real := 1.0 - r * r
	return sqrt((1.0 + damped * damped) / (real * real + damped * damped))


## Adopts the powertrain's current motor speeds. Called by DroneCore every step: the four rpms are
## the model's only input, and the fact that they differ under manoeuvre is what makes the output a
## beating signal rather than a single sine.
func set_rpm(motor_rpm: Dictionary) -> void:
	for i in MotorLayout.MOTOR_NAMES.size():
		rpm[i] = float(motor_rpm.get(MotorLayout.MOTOR_NAMES[i], 0.0))


## The body-axis angular rate the airframe is shaking the sensor with at this instant, rad/s.
##
## Called once per SENSOR SAMPLE (see vibration_source.gd), so anything here above the sensor's
## Nyquist folds down on its own — which is exactly what happens to blade passage at high throttle
## on a 1 kHz gyro, and is a real reason firmware runs gyros faster than the loop.
func angular_rate_at(t_s: float) -> Vector3:
	var dt := t_s - _last_t
	_last_t = t_s

	var out := Vector3.ZERO
	for i in 4:
		var hz := rpm[i] / 60.0
		if hz <= 0.0:
			continue

		_phase[i] += TAU * hz * dt
		var omega := TAU * hz
		# m * r * omega^2 — the rotating-imbalance forcing, exactly. Everything rpm-dependent
		# about the amplitude of this model is this one line.
		var per_kg_n := prop_radius_m * omega * omega

		var bp_hz := blades * hz
		var imbalance_n := imbalance_kg * per_kg_n \
			* modal_gain(hz, resonance_hz, damping_ratio) * mount_transmissibility(hz)
		# Blade passage acts at blades x rotation but its MAGNITUDE is set by the loading at
		# rotation, so the omega^2 above is the right one and only the frequency is multiplied.
		# The modal gain and the pad, on the other hand, are asked about the frequency that is
		# actually arriving — which is what lets blade pass sit on the frame mode while the 1x
		# line is nowhere near it.
		var blade_n := blade_pass_kg * per_kg_n \
			* modal_gain(bp_hz, resonance_hz, damping_ratio) * mount_transmissibility(bp_hz)

		var theta: float = _phase[i] + PHASE_OFFSETS[i]
		var bending := imbalance_n * sin(theta) + blade_n * sin(blades * theta)
		var torsion := imbalance_n * cos(theta) + blade_n * cos(blades * theta)

		out += _axis[i] * (bending * SENSOR_RESPONSE_RAD_S_PER_N)
		out.y += torsion * SENSOR_RESPONSE_RAD_S_PER_N * YAW_COUPLING * _yaw_sign[i]

	return out


## Back to t = 0 with every phase where it started. Gyro.reset() calls this, and without it a
## respawn would continue the previous flight's shake — which would break "the same flight twice"
## from a place nobody would think to look.
func reset() -> void:
	_last_t = 0.0
	for i in 4:
		_phase[i] = 0.0


## The direction each arm's bending shows up along, in body axes.
##
## An arm is far more compliant in BENDING (out of the frame's plane) than in its own plane, so the
## response to a tip force is taken along the vertical, and the rotation that produces is
## r x y_hat for that arm's position — normalised, because the magnitude is already carried by
## SENSOR_RESPONSE_RAD_S_PER_N and having it here too would make the compliance constant
## secretly depend on arm length.
##
## This is the least defensible geometric choice in the file. The honest alternative was a full
## modal shape, which needs data that does not exist; this at least makes the four arms point in
## four different directions, which is what stops the model collapsing into one sine.
func _set_geometry(arm_m: float) -> void:
	_axis.clear()
	for name in MotorLayout.MOTOR_NAMES:
		var r := MotorLayout.motor_position(name, arm_m)
		var bending := r.cross(Vector3(0.0, 1.0, 0.0))
		_axis.append(bending.normalized() if bending.length() > 0.0 else Vector3.ZERO)
