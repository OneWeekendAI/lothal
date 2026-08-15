#!/usr/bin/env python3
"""Measure a frame's first arm-bending mode AND its damping from an impact test (LTHL-49).

===========================================================================
WHAT THIS IS FOR, AND WHY IT IS NOT resonance_analysis.py
===========================================================================

VibrationModel.REFERENCE_RESONANCE_HZ is 180.0 and its own comment says "No source. There is
no source." VibrationModel.DEFAULT_DAMPING_RATIO is 0.03 and is the middle of a published
range for bolted assemblies, which is a better provenance than none and is still not a
measurement. Because the first cannot be checked, RateTune.kd_ceiling_for refuses to let
vibration move the D gains at all.

tools/resonance_analysis.py tried to get the frequency from a flight log and returned a null
result twice. The instrument works; no admissible log exists. Five admissibility criteria,
and the binding one was (d), a slow throttle sweep: in normal flying the 1x line moves
155-235 Hz WITHIN one 1.024 s analysis frame, up to 240 FFT bins of smear, so there is no
line for order tracking to ride. A fifth log from a different pilot, quad and year reproduced
the wall independently.

AN IMPULSE HAS NO HARMONICS TO TRACK. That is the entire reason this file exists. A strike
excites every mode at once and the answer is read off the ringdown. Nothing rotates, so there
is no rpm to log, no sweep to fly, and the order-tracking discriminator that all five criteria
existed to feed is simply not needed:

    criterion            flight log                      impact test
    a. unfiltered gyro   firmware config, easy to fumble trivially satisfied
    b. named frame       THE BINDING BLOCKER             you own it; use calipers
    c. named motors      same problem                    same answer
    d. slow sweep        never once satisfied            DOES NOT EXIST
    e. logged rpm        competes with (a) for debug[]   DOES NOT EXIST

This is classical experimental modal analysis, and it is cheap: a frame, a screwdriver handle,
and either the aircraft's own gyro or a phone microphone.

SECOND PRIZE, AND IT IS FREE. A ringdown carries the damping in its decay envelope. Frequency
and damping come out of ONE recording, so two of the vibration model's three named guesses
fall to one measurement.

===========================================================================
PRE-REGISTRATION. WRITTEN AND COMMITTED BEFORE ANY RECORDING EXISTS.
===========================================================================

Same discipline as ThrustValidation, BuildValidation and resonance_analysis: the bound is
fixed in advance so the git history shows it was chosen blind. If the measurement busts the
bound, that is reported and diagnosed. It is NOT widened, and REFERENCE_RESONANCE_HZ is not
retuned to whatever came out — that converts a measurement into a fit and destroys the only
thing this slice earns. A bound moved to fit the data it measures is not a bound.

There is a process note from LTHL-18 being honoured here. Last time the instrument fix and the
data survey landed in the same commit (a9b3fa4), so the claim that the statistic predated the
data rested on the write-up rather than on git. THIS FILE AND ITS SELF-TEST ARE COMMITTED
ALONE AND FIRST. The ordering is then verifiable rather than asserted.

---------------------------------------------------------------------------
1. THE BOUND: 20%, DERIVED FROM ITS OWN TERMS. IT DOES NOT INHERIT 25%.
---------------------------------------------------------------------------

resonance_analysis.AGREEMENT_FRACTION is 0.25, decomposed for a FLIGHT measurement. Reusing it
here by default would be exactly the sloppiness the pre-registration discipline exists to stop:
some of its terms are properties of the structure and transfer unchanged, some are properties
of how the structure was excited and do not transfer at all, and two terms exist here that did
not exist there. Term by term, each as its effect on frequency:

  * Root fixity.  TRANSFERS, UNCHANGED, +-10%.  Still the largest term and still the least
    reducible. The flight version was about the pilot's bolt torque; this version is about the
    clamp. Those are not the same uncertainty but they are the same SIZE and the same kind: a
    real cantilever root is somewhere between clamped and pinned, and it moves with a hex key.
    The test clamps the centre plate stack — see section 2 — which is stiffer than the plates
    are in flight, and that difference lands here.
  * Arm length definition.  TRANSFERS BUT SHRINKS, +-2% in L, and f goes as L^-1.5, so +-3%.
    The flight bound carried +-5% in L because frames.json's arm_m is a published figure whose
    convention the manufacturer does not state. Here the frame is in your hand: the protocol
    requires the arm measured with calipers, hub face to motor shaft centre, and the number
    written down. The definitional ambiguity is measured away. What is left is where the root
    effectively is, which is not the same question as where the clamp is.
  * The dropped arm-mass term.  TRANSFERS, 5%.  vibration_model.gd drops (33/140)*m_arm from
    the effective mass, a 7% correction on the reference build that varies down the catalog.
    It is a transport error BETWEEN frames, so it enters only when the frame measured is not
    the reference build. It is carried anyway: assuming the frame in hand is the reference
    build would be assuming the thing the measurement is for.
  * Unpublished tip mass.  DOES NOT TRANSFER. DROPS TO ~0.  The flight bound carried -5%
    because mounting hardware, wires and TPU are not in any catalog. The protocol puts the
    motor, its hardware and the prop on a kitchen scale and records the number. A quantity you
    weighed is not a quantity you are uncertain about. Retained at +-1% for scale error, which
    is +-0.5% in f.
  * Peak picking.  DOES NOT TRANSFER. REPLACED, AND MUCH SMALLER: +-1.5%.  This is the term
    the whole method changes. The flight version read a smeared harmonic off a spectrogram and
    was worth +-3% at best, bounded by the 6% half-power bandwidth. A ringdown gives an
    isolated decaying sinusoid, and its frequency is estimated from the PHASE SLOPE of the
    analytic signal over several tens of cycles, not from an FFT bin — see section 4. The
    self-test recovers planted frequencies to well inside 1%.
  * NON-ROTATING. NEW TERM, +-3%.  Gyroscopic stiffening from spinning props is present in
    flight and absent from a tap test, so this measures a slightly different mode than the one
    the model is about. Order of magnitude, for the reference build: prop polar inertia
    I_p ~ m L^2/12 = 4.5 g over a 127 mm span = 6.0e-6 kg m^2; motor bell adds ~3e-6
    transverse. A tip-loaded cantilever's tip TILTS as well as translates, theta = 1.5 y / L,
    so the tilt inertia is worth I_t (1.5/L)^2 = 1.7e-3 kg against 36.5 g of translating tip
    mass — about 4.6% of the modal mass. The whirl split I_p Omega / (2 I_t omega_n) is order
    0.6 at 20k rpm, and 0.6 * 0.046 is 3%. This is an ESTIMATE, stated as one, and it is
    carried as a symmetric term because forward and backward whirl split in opposite
    directions and a tap test sits between them. It is written down here, before any data, so
    it is a known bounded deviation rather than something discovered while explaining a
    disagreement.

Every throttle-sweep term from the flight bound — coverage, order-curve trend removal, the
smear — has no counterpart here and contributes nothing.

  sqrt(10^2 + 3^2 + 5^2 + 0.5^2 + 1.5^2 + 3^2) = 12.1%, call it 12% for one standard deviation.

The bound is set at 20%, the same ~1.7 sigma convention resonance_analysis used, so the two
numbers are comparable rather than differently generous. And the same caveat is repeated
plainly because it has not gone away: 160 Hz against 180 Hz is 11% and would PASS. THIS
MEASUREMENT STILL CANNOT SETTLE THE 12% QUESTION kd_ceiling_for's comment raises. What it can
do is catch an anchor that is wrong by more than a build's own spread, which is what 180 Hz
being unsourced actually risks, and it does it at a third of the flight bound's width.
"""

IMPACT_AGREEMENT_FRACTION = 0.20

"""
---------------------------------------------------------------------------
1b. THE DAMPING BOUND: a factor of two, and why it is so loose
---------------------------------------------------------------------------

DEFAULT_DAMPING_RATIO = 0.03 is the middle of the 0.02-0.05 conventionally quoted for bolted
assemblies. The published RANGE is already a factor of 2.5 wide, so a bound tighter than the
literature it is checked against would be theatre. What a measurement can do here is say
whether a real quad arm sits inside that range at all or is somewhere else entirely — carbon
laminate on its own is zeta well under 0.01, and if the joints turn out not to dominate then
0.03 is wrong by a lot and in a knowable direction.

  * The estimator itself.  Log decrement over a decade of amplitude decay, +-10%. Bounded by
    how well the envelope is exponential, which is reported as an R^2 per fit and gated below.
  * Which joint.  +-30%. Damping is dominated by the bolted root and varies with torque far
    more than frequency does. This is not reducible by measuring more carefully.
  * Air damping and the strike itself.  +-20%. A tap couples energy out through the striker
    and the clamp; both add apparent damping, one-signed, so a measured zeta is an UPPER
    bound on the structure's own.

That is a factor of ~1.6 at one sigma, taken to 2.0 for the same 1.7 sigma convention.
Reported as a ratio, never as a pass on a percentage.
"""

DAMPING_AGREEMENT_FACTOR = 2.0

"""
---------------------------------------------------------------------------
2. THE METHOD DECISIONS. Each of these moves the answer.
---------------------------------------------------------------------------

A number measured under unstated conditions is not a measurement. All five decisions are made
here, before any recording, and each is argued rather than defaulted.

  (i) BOUNDARY CONDITION: CLAMPED AT THE CENTRE PLATES. Not free-free, not hand-held.
      vibration_model.gd is explicitly a cantilever ROOTED AT THE CENTRE PLATES, so the test
      must root it there or it measures a different structure. Free-free — the frame hung on
      elastic — is the cleanest boundary condition in modal testing and is REJECTED anyway,
      because its low modes are whole-airframe modes (plate bending, arms in anti-phase) and
      not the arm cantilever the model is about; it would answer a question nobody asked.
      Hand-held is REJECTED because a hand is neither clamped nor free: it adds soft-tissue
      damping directly at the root, which inflates zeta — the quantity this test also wants —
      and it lowers f by an amount that changes with grip. The difference is not small and it
      is not repeatable, which is worse.
      So: the centre plate stack is clamped, the arm under test hangs free, the stack bolts are
      at flying torque. The residual clamp-versus-plates difference is the +-10% root fixity
      term above and is the honest cost of the choice.

 (ii) ASSEMBLED, WITH MOTORS ON. NOT A BARE FRAME. The model is a TIP-LOADED cantilever whose
      reference tip mass is 36.5 g — a 2207 plus a 5x4.3x3. A bare arm has a different modal
      mass and rings at a completely different frequency; it is a different mode, not a noisier
      version of the same one. Motors are bolted on at flying torque, with their wires routed
      as flown.

(iii) PROPS: BOTH, DELIBERATELY, AND THE PAIR IS ITSELF A MEASUREMENT. The reference tip mass
      includes a prop, so props-on is the configuration the model describes. But the gyro route
      (section 3) needs the aircraft armed, and arming with props fitted for a bench test is not
      something this file will ask a person to do. The resolution is not a compromise, it is a
      free extra check:
        - the GYRO recording is made PROPS OFF, and its frequency is converted to the props-on
          figure by the sqrt mass law, f_on = f_off * sqrt(m_off / m_on);
        - the MICROPHONE recording is made BOTH WAYS, and the measured ratio f_off / f_on tests
          that conversion directly.
      This imports the sqrt(m) exponent into the gyro number, and that is stated rather than
      hidden. It does not import the ANCHOR, which is the thing under test, and the exponent is
      textbook rather than guessed. If the microphone pair disagrees with sqrt by more than
      TIP_MASS_SHIFT_TOLERANCE, the conversion is reported as unvalidated and the props-off
      number is reported raw.

 (iv) NON-ROTATING, AND BOUNDED IN ADVANCE. Nothing spins during a tap test, so gyroscopic
      stiffening is absent. Estimated at 3% in section 1 and carried in the bound as a term.
      Written down before the data so it cannot become an excuse afterwards.

  (v) WHERE TO STRIKE, WHERE TO LISTEN, AND HOW THE FIRST BENDING MODE IS IDENTIFIED. This is
      the single most likely place to accidentally pick the number that agrees, so the rule is
      written before any spectrum is seen and is implemented in identify_first_bending() below
      rather than applied by eye.

      Strike: on the arm, just inboard of the motor mount, with the plastic handle of a
      screwdriver. Perpendicular to the arm's plane (VERTICAL) for the primary configuration,
      and in-plane (LATERAL) for the discriminator configuration. Listen: the flight
      controller's own gyro, or a phone microphone — see section 3.

      A tap excites every mode at once, which is the point and is also the problem: the
      spectrum will hold the arm's first bending mode, its second, plate modes, motor bell
      modes, prop blade modes and, on the microphone, the room. THE RULE, PRE-REGISTERED:

        The frame's first arm bending mode is the LOWEST candidate peak in SEARCH_BAND_HZ that
        satisfies all THREE of the following, each of which is a physical prediction that a
        wrong candidate has no reason to satisfy:

          (a) FOUR-ARM CONSISTENCY. It appears on every arm struck, within
              ARM_CONSISTENCY_FRACTION. Four nominally identical cantilevers must ring at
              nominally the same frequency. A plate mode, a bench mode or a room resonance is
              shared across arms too — so this criterion alone proves nothing and is why there
              are three.
          (b) DIRECTIONAL. Its amplitude under the vertical strike is at least
              DIRECTION_RATIO times its amplitude under the lateral strike. An arm is wider
              than it is thick, so its first bending mode is out of plane, and a vertical tap
              must excite it far harder than an in-plane one. A room resonance, a plate mode
              or the bench does not care which way the screwdriver went.
          (c) TIP-MASS SENSITIVE. Removing the prop shifts it UP by sqrt(m_on / m_off), within
              TIP_MASS_SHIFT_TOLERANCE. This is the strongest of the three: an arm mode MUST
              move by the mass law, a prop blade mode DISAPPEARS entirely, and a plate mode,
              an acoustic mode or a mains hum does not move at all.

        If no candidate satisfies all three, the answer is NO MODE IDENTIFIED. That is a valid
        and reportable outcome — the equivalent of resonance_analysis's null result — and it is
        very much better than the lowest prominent peak, which is what a tool that always
        returns a number would hand back.

---------------------------------------------------------------------------
3. HOW IT IS RECORDED. THE GYRO ROUTE IS PREFERRED.
---------------------------------------------------------------------------

  * MICROPHONE (a phone, 44.1/48 kHz WAV). Needs no electronics at all, so it is the only route
    for a bare frame or a frame with no FC in it, and it is the route that does the props-on
    half of decision (iii). It measures room acoustics as much as it measures the frame, which
    is exactly what criteria (b) and (c) are built to reject.
  * THE QUAD'S OWN GYRO. PREFERRED, STRONGLY. It measures the response AT THE SENSOR THAT
    ACTUALLY MATTERS — the same path vibration_model.gd models, downstream of the same mount,
    through the same soft-mount grommets. It removes the room entirely.

    AND IT HAS A TRAP THAT LTHL-18 ALREADY FOUND: on the reference build the modelled mode sits
    ABOVE the gyro's own 150 Hz lowpass, so the flight controller never sees most of it. The
    protocol therefore requires the gyro lowpass OFF, and this file REFUSES a log whose gyro
    is measurably filtered in the band it is looking in. That check is not rewritten here:
    resonance_analysis._choose_gyro_columns and _looks_prefilter decide pre-filter status from
    MEASURED BAND POWER rather than from the header, because the debug_mode enum shifts between
    firmware versions and a header can lie. They are imported and reused. There is deliberately
    no second, header-trusting implementation in this codebase.

    What is NOT reused is resonance_analysis.load_betaflight, because it requires eRPM columns
    and refuses a log without them. Nothing rotates in an impact test, so that requirement is
    meaningless here — hence load_betaflight_impact() below, which reuses the same reader and
    the same filtering evidence and drops only the rpm demand.

---------------------------------------------------------------------------
4. PRE-REGISTERED ANALYSIS PARAMETERS
---------------------------------------------------------------------------

Fixed here so nothing can be nudged after seeing a spectrum.

  * STRIKE DETECTION. An onset is where the signal envelope exceeds ONSET_RATIO times its own
    median, with STRIKE_REFRACTORY_S of dead time after each so one impact is not counted as
    several. Strikes are analysed individually and combined at the end; a strike is never
    averaged into another in the time domain, because the phase of two taps is unrelated and
    averaging them would cancel the very thing being measured.
  * BLANKING. BLANK_S after onset is discarded. The contact transient is the striker and the
    contact stiffness, not the structure, and it is broadband enough to contaminate every
    candidate.
  * WINDOW. ANALYSIS_WINDOW_S of ringdown after the blank. At zeta = 0.03 and 180 Hz the
    amplitude time constant is 29 ms, so 0.25 s is about eight of them: long enough to fit a
    decade of decay, short enough that the next strike cannot enter the window.
  * DETECTION WINDOWS: DETECTION_WINDOWS_S, a short one and a long one, candidates unioned.
    How long a ringdown lasts is a property of the MODE, not of the analysis: 143 Hz at
    zeta = 0.03 rings for 100 ms, 420 Hz at zeta = 0.05 is finished in 20 ms and is buried by a
    long frame's integrated noise. One length cannot see both. Also found by the self-test
    before any real data — the 420 Hz planted mode was invisible at 0.25 s and stands 7.6x
    above trend at 0.05 s.
  * WINDOW: RECTANGULAR WITH A COSINE TAPER ON THE TAIL ONLY, TAIL_TAPER_FRACTION of the
    frame. Not Hann, and the difference is not cosmetic. resonance_analysis uses Hann because
    it analyses a stationary signal; a ringdown is the opposite shape, starting at full
    amplitude and decaying, so a Hann window weights to zero exactly the part that carries the
    energy. A 420 Hz mode at zeta = 0.05 is over inside 8% of the frame and Hann-weighting
    deleted it entirely — the planted mode was not even a candidate. Caught by the self-test,
    on synthetic data with a known answer, before any real recording existed, which is what
    synthetic data is for. It moved nothing about the bound.
  * CANDIDATE PEAKS. A peak in SEARCH_BAND_HZ standing at least CANDIDATE_PROMINENCE above the
    running median of the same spectrum, with peaks inside 6% of an accepted one treated as
    the same feature's shoulder. The band is (60, 600) Hz, the SAME band resonance_analysis
    uses and for the same reasons: below is rigid-body and handling, above is beyond the first
    bending mode of any 3-10" arm.
  * FREQUENCY ESTIMATE. NOT AN FFT BIN. Each candidate is bandpassed (zero-phase, in the
    frequency domain, cosine-tapered edges), converted to its analytic signal, and the
    frequency is the slope of its UNWRAPPED PHASE over the fit span. A 0.25 s window has 4 Hz
    bins, which would be worth +-2% by itself; the phase slope over ~40 cycles is worth far
    less than the 1.5% the bound allows, and the self-test measures that claim rather than
    asserting it.
  * BANDPASS. Zero-phase, cosine-tapered, and its width MATCHED TO THE DAMPING in a second
    pass — BANDPASS_HALF_WIDTHS half-power half-widths, never narrower than the fixed
    fractional width. A band too narrow for a heavily damped mode truncates its skirts and
    biases zeta LOW, which is the flattering direction. See fit_mode.
  * DAMPING ESTIMATE. Log decrement: a straight line fitted to ln(envelope) against time over
    the same span, from the envelope peak down to ENV_FLOOR_RATIO of it, and
    zeta = -slope / (2 pi f). The span must cover at least MIN_FIT_CYCLES cycles.
  * A FIT IS REJECTED unless the log-envelope fit has R^2 >= MIN_DECAY_R2 and the recovered
    zeta lies in ZETA_PLAUSIBLE. THIS IS A DISCRIMINATOR, NOT HOUSEKEEPING: a mains hum, a
    logging-rate artefact or a room tone does not decay, so it fails the R^2 gate; a beat
    between two close modes decays non-monotonically and fails it too. "It rang and then it
    stopped ringing, exponentially" is most of what makes something a mode.
  * COMBINING STRIKES. Candidates from separate strikes are grouped when within
    GROUP_TOLERANCE of each other, and a group is only reported if it appears in at least
    MIN_STRIKE_FRACTION of the strikes in that recording. Median across strikes, and the
    spread is printed — if repeat taps on the same arm disagree, that is information and it is
    not to be hidden behind a mean.
  * NO AVERAGING ACROSS ARMS for the reported number: the four arms are reported separately
    and their agreement is criterion (a). An arm that disagrees is a finding about the frame.

---------------------------------------------------------------------------
5. UNITS
---------------------------------------------------------------------------

A microphone WAV is in arbitrary units and only ever used for FREQUENCY RATIOS and for
relative amplitude between two strike directions, both of which are scale-free. Gyro data is
deg/s from Betaflight and rad/s from Lothal, converted once in the loader as resonance_analysis
does. No absolute amplitude from any route is quoted anywhere, because
SENSOR_RESPONSE_RAD_S_PER_N in vibration_model.gd sets the y-axis units and is itself circular.
Frequency and damping are both scale-invariant, which is the entire reason this measurement is
worth anything at all.
"""

SEARCH_BAND_HZ = (60.0, 600.0)

ONSET_RATIO = 8.0
STRIKE_REFRACTORY_S = 0.40
BLANK_S = 0.005
ANALYSIS_WINDOW_S = 0.25
DETECTION_WINDOWS_S = (0.05, 0.25)

TAIL_TAPER_FRACTION = 0.10
CANDIDATE_PROMINENCE = 4.0
SPECTRUM_TREND_BINS = 41
PEAK_MERGE_FRACTION = 0.06

BANDPASS_HALF_FRACTION = 0.15
BANDPASS_MIN_HALF_HZ = 15.0
BANDPASS_HALF_WIDTHS = 7.0
ENV_FLOOR_RATIO = 0.10
MIN_FIT_CYCLES = 5.0
MIN_DECAY_R2 = 0.90
ZETA_PLAUSIBLE = (0.001, 0.30)

GROUP_TOLERANCE = 0.06
MIN_STRIKE_FRACTION = 0.6

ARM_CONSISTENCY_FRACTION = 0.10
DIRECTION_RATIO = 2.0
TIP_MASS_SHIFT_TOLERANCE = 0.03

RAD_TO_DEG = 57.29577951308232

import argparse
import json
import math
import os
import sys
import wave
from dataclasses import dataclass, field

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    sys.exit("numpy is required: python3 -m venv .venv && .venv/bin/pip install numpy")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# The filtering evidence is imported, never reimplemented. See pre-registration 3.
from resonance_analysis import (  # noqa: E402
    REFERENCE_ARM_M,
    REFERENCE_RESONANCE_HZ,
    REFERENCE_TIP_MASS_KG,
    _choose_gyro_columns,
    _read_bbl_csv,
    check_uniform_sampling,
    _running_median,
    resonance_hz_for,
)

DEFAULT_DAMPING_RATIO = 0.03  # transcribed from src/sim/vibration_model.gd, as above


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------


@dataclass
class Recording:
    """One recording of one configuration. Everything below this is source-blind."""

    name: str
    source: str  # "wav" | "betaflight" | "lothal" | "inav" | "synthetic"
    sample_rate_hz: float
    signal: "np.ndarray"
    #: What was struck and how, so a result can never be quoted without its conditions.
    arm: str = "?"
    direction: str = "vertical"  # "vertical" | "lateral"
    props: bool = True
    unfiltered: bool = True
    unfiltered_evidence: str = "n/a (acoustic)"
    #: What check_uniform_sampling measured, carried and printed exactly as the filtering
    #: evidence is. It matters MORE here than in resonance_analysis: damping comes from the
    #: decay envelope, and a hole in a decaying exponential changes the apparent decay rate,
    #: not just the frequency.
    sampling_evidence: str = "n/a (constant-rate stream)"
    header: dict = field(default_factory=dict)


def load_wav(path: str, **meta) -> Recording:
    """A phone recording. Mono, or the mean of the channels — a tap is not stereo information."""
    with wave.open(path, "rb") as wf:
        fs = float(wf.getframerate())
        width = wf.getsampwidth()
        channels = wf.getnchannels()
        raw = wf.readframes(wf.getnframes())
    dtype = {1: np.uint8, 2: np.int16, 4: np.int32}.get(width)
    if dtype is None:
        raise ValueError(f"{path}: {width*8}-bit WAV is not supported; export 16- or 24-bit")
    x = np.frombuffer(raw, dtype=dtype).astype(float)
    if dtype is np.uint8:
        x -= 128.0
    if channels > 1:
        x = x.reshape(-1, channels).mean(axis=1)
    return Recording(name=os.path.basename(path), source="wav", sample_rate_hz=fs,
                     signal=x - x.mean(), **meta)


def load_betaflight_impact(path: str, axis: str = "roll", **meta) -> Recording:
    """A decoded blackbox CSV from a bench tap, with NO rpm requirement.

    resonance_analysis.load_betaflight refuses a log with no eRPM columns, correctly, because
    order tracking cannot work without rpm. Nothing rotates here, so that requirement is
    meaningless and this loader drops it — and ONLY it. The gyro-filtering evidence comes from
    the same _choose_gyro_columns, which decides from measured band power rather than from the
    header, so an impact log gets exactly the same scrutiny a flight log got.
    """
    header, names, rows = _read_bbl_csv(path)
    col = {n: i for i, n in enumerate(names)}
    t_us = rows[:, col["time (us)"]] if "time (us)" in col else rows[:, 0]
    dt, sampling_evidence = check_uniform_sampling(t_us, path, 1e-6)
    fs = 1.0 / dt
    unfiltered, evidence, roll_key, pitch_key = _choose_gyro_columns(header, col, rows, fs)
    key = roll_key if axis == "roll" else pitch_key
    return Recording(
        name=header.get("Craft name", os.path.basename(path)),
        source="betaflight",
        sample_rate_hz=fs,
        signal=rows[:, col[key]],
        unfiltered=unfiltered,
        unfiltered_evidence=evidence,
        sampling_evidence=sampling_evidence,
        header=header,
        **meta,
    )


def load_lothal_impact(path: str, axis: str = "roll", **meta) -> Recording:
    """A FlightRecorder log: '#'-commented JSON header lines, then CSV. rad/s -> deg/s here."""
    header_text, names, data_lines = "", None, []
    with open(path) as fh:
        for line in fh:
            if names is None and line.startswith("#"):
                header_text += line[1:].rstrip("\n")
                continue
            if names is None:
                names = line.strip().split(",")
                continue
            data_lines.append(line)
    if names is None:
        raise ValueError(f"{path}: no CSV header row found")
    header = json.loads(header_text)
    rows = np.loadtxt(data_lines, delimiter=",")
    col = {n: i for i, n in enumerate(names)}
    # Header-stated rate, row-measured uniformity. t_s is in SECONDS. Same reasoning as
    # resonance_analysis.load_lothal.
    _, sampling_evidence = check_uniform_sampling(rows[:, col["t_s"]], path, 1.0)
    key = "gyro_x_rad_s" if axis == "roll" else "gyro_z_rad_s"
    lp = header.get("gyro", {}).get("lowpass_hz")
    return Recording(
        name=header.get("aircraft", {}).get("fingerprint", os.path.basename(path)),
        source="lothal",
        sample_rate_hz=float(header.get("sample_rate_hz", 1000.0)),
        signal=rows[:, col[key]] * RAD_TO_DEG,
        unfiltered=lp is None or float(lp) <= 0.0 or float(lp) >= 500.0,
        unfiltered_evidence=f"header gyro lowpass: {lp if lp is not None else 'absent'}",
        sampling_evidence=sampling_evidence,
        header=header,
        **meta,
    )


def assert_usable(rec: Recording) -> None:
    """Refuse a filtered gyro recording, loudly. See pre-registration 3.

    A gyro lowpass attenuates exactly the band this analysis hunts in — on the reference build
    the modelled mode is ABOVE Betaflight's 150 Hz default — so a filtered recording produces
    a missing or suppressed peak and the conclusion drawn would be that the model is wrong when
    in fact the data is.
    """
    if rec.unfiltered:
        return
    nyquist = rec.sample_rate_hz * 0.5
    sys.exit(
        f"REFUSED: {rec.name} ({rec.source}) has FILTERED gyro data.\n"
        f"  {rec.unfiltered_evidence}\n"
        f"  the search band is {SEARCH_BAND_HZ[0]:.0f}-{min(SEARCH_BAND_HZ[1], nyquist):.0f} Hz "
        "and a lowpass sits inside it.\n"
        "Re-record with gyro_lpf1_type = OFF and gyro_lpf1_static_hz = 0 (protocol step 4)."
    )


# ---------------------------------------------------------------------------
# Signal machinery. numpy only, no scipy — this has to run wherever the repo runs.
# ---------------------------------------------------------------------------


def analytic_signal(x):
    """Hilbert transform by the standard one-sided-spectrum construction."""
    n = len(x)
    spectrum = np.fft.fft(x)
    h = np.zeros(n)
    h[0] = 1.0
    if n % 2 == 0:
        h[n // 2] = 1.0
        h[1:n // 2] = 2.0
    else:
        h[1:(n + 1) // 2] = 2.0
    return np.fft.ifft(spectrum * h)


def bandpass(x, fs, centre_hz, half_hz):
    """Zero-phase brick wall with cosine-tapered edges, applied in the frequency domain.

    Zero-phase matters: a causal filter's group delay would distort the very decay envelope
    being fitted, and would do it differently at different frequencies.
    """
    n = len(x)
    freqs = np.fft.rfftfreq(n, 1.0 / fs)
    lo, hi = centre_hz - half_hz, centre_hz + half_hz
    taper = 0.25 * half_hz
    mask = np.zeros(len(freqs))
    inner = (freqs >= lo) & (freqs <= hi)
    mask[inner] = 1.0
    left = (freqs >= lo - taper) & (freqs < lo)
    mask[left] = 0.5 * (1.0 + np.cos(np.pi * (lo - freqs[left]) / taper))
    right = (freqs > hi) & (freqs <= hi + taper)
    mask[right] = 0.5 * (1.0 + np.cos(np.pi * (freqs[right] - hi) / taper))
    return np.fft.irfft(np.fft.rfft(x) * mask, n=n)


# ---------------------------------------------------------------------------
# Strikes
# ---------------------------------------------------------------------------


def find_strikes(x, fs):
    """Onset sample indices. See pre-registration 4."""
    env = np.abs(analytic_signal(x - np.mean(x)))
    smooth = int(max(1, round(0.002 * fs)))
    env = np.convolve(env, np.ones(smooth) / smooth, mode="same")
    floor = np.median(env)
    if floor <= 0:
        floor = np.mean(env) if np.mean(env) > 0 else 1e-30
    above = env > ONSET_RATIO * floor
    refractory = int(round(STRIKE_REFRACTORY_S * fs))
    onsets, i = [], 0
    while i < len(above):
        if above[i]:
            # Walk back to where the envelope actually left the floor, so the blanking
            # interval starts at the impact and not partway up its rise.
            j = i
            while j > 0 and env[j] > 2.0 * floor:
                j -= 1
            onsets.append(j)
            i += refractory
        else:
            i += 1
    return onsets


@dataclass
class ModeFit:
    hz: float
    zeta: float
    prominence: float  # spectral magnitude over the running-median trend
    amplitude: float  # envelope peak in the bandpassed ringdown, arbitrary units
    r2: float
    cycles: float


def ringdown_window(n):
    """Rectangular, with a cosine taper on the TAIL ONLY. See pre-registration 4.

    NOT a Hann window, and this was found by synthetic data with a known answer before any real
    recording existed — the same way LTHL-18's median statistic was found to be broken. A Hann
    window is right for a stationary signal and exactly wrong for a ringdown: it weights the
    START of the frame to zero, and the start of a ringdown is where all of its energy is. A
    mode at 420 Hz and zeta = 0.05 has an amplitude time constant of 7.6 ms, so it is over
    inside the first 8% of a 0.25 s frame, and Hann-weighting deleted it outright — the planted
    mode did not appear as a candidate at all and the analyser reported the noise floor instead.

    A ringdown already begins at full amplitude and ends at nothing, so it needs no taper at the
    start and only enough at the end to stop the discontinuity ringing across the spectrum.
    """
    w = np.ones(n)
    tail = max(2, int(round(TAIL_TAPER_FRACTION * n)))
    w[-tail:] = 0.5 * (1.0 + np.cos(np.pi * np.arange(tail) / tail))
    return w


def candidate_peaks(window, fs):
    """Peaks in the ringdown spectrum, coarse. Refinement happens per-candidate afterwards."""
    n = len(window)
    spec = np.abs(np.fft.rfft(window * ringdown_window(n)))
    freqs = np.fft.rfftfreq(n, 1.0 / fs)
    band = (freqs >= SEARCH_BAND_HZ[0]) & (freqs <= min(SEARCH_BAND_HZ[1], fs * 0.45))
    if band.sum() < 8:
        return []
    f, s = freqs[band], spec[band]
    trend = np.maximum(_running_median(s, SPECTRUM_TREND_BINS), 1e-30)
    ratio = s / trend
    out, taken = [], []
    for i in np.argsort(ratio)[::-1]:
        if ratio[i] < CANDIDATE_PROMINENCE:
            break
        if any(abs(f[i] - t) < PEAK_MERGE_FRACTION * t for t in taken):
            continue
        taken.append(f[i])
        out.append((float(f[i]), float(ratio[i])))
    return sorted(out)


def _fit_at_bandwidth(window, fs, centre_hz, half, prominence):
    """One pass of the fit at a given bandpass half-width. See fit_mode for why there are two."""
    z = analytic_signal(bandpass(window, fs, centre_hz, half))
    env = np.abs(z)
    if not np.any(env > 0):
        return None
    peak_i = int(np.argmax(env))
    peak = env[peak_i]
    below = np.where(env[peak_i:] < ENV_FLOOR_RATIO * peak)[0]
    end_i = peak_i + (int(below[0]) if len(below) else len(env) - peak_i)
    span = env[peak_i:end_i]
    if len(span) < 8:
        return None
    t = np.arange(len(span)) / fs
    cycles = centre_hz * (len(span) / fs)
    if cycles < MIN_FIT_CYCLES:
        return None

    ln_env = np.log(np.maximum(span, 1e-30))
    slope, intercept = np.polyfit(t, ln_env, 1)
    predicted = slope * t + intercept
    ss_res = float(np.sum((ln_env - predicted) ** 2))
    ss_tot = float(np.sum((ln_env - ln_env.mean()) ** 2))
    r2 = 1.0 - ss_res / ss_tot if ss_tot > 0 else 0.0

    phase = np.unwrap(np.angle(z[peak_i:end_i]))
    f_slope, _ = np.polyfit(t, phase, 1)
    hz = float(f_slope / (2.0 * np.pi))
    if not (SEARCH_BAND_HZ[0] <= hz <= SEARCH_BAND_HZ[1]):
        return None
    zeta = float(-slope / (2.0 * np.pi * hz))

    if not (ZETA_PLAUSIBLE[0] <= zeta <= ZETA_PLAUSIBLE[1]):
        return None
    return ModeFit(hz=hz, zeta=zeta, prominence=prominence, amplitude=float(peak),
                   r2=float(r2), cycles=float(cycles))


def fit_mode(window, fs, centre_hz, prominence):
    """Frequency from phase slope, damping by log decrement. See pre-registration 4.

    TWO PASSES, BECAUSE THE RIGHT BANDWIDTH DEPENDS ON THE DAMPING THAT IS BEING MEASURED. A
    decaying sinusoid is Lorentzian in frequency with a half-power half-width of zeta*f, so a
    fixed fractional bandpass is too narrow for a heavily damped mode and truncates its skirts —
    which distorts the early, steep part of the envelope and biases the damping LOW, in the
    direction that would make the frame look better than it is. Measured on the synthetic 420 Hz
    / zeta = 0.05 mode: at +-0.15f the fit gives zeta = 0.041 with R^2 = 0.89 and is rejected;
    widened to match, it gives 0.046 at R^2 = 0.97.

    So: pass one at the fixed fractional width to get a first zeta, pass two at a width matched
    to it. The width can only ever GROW between passes — a rule that could narrow the band
    around a mode would let a bad first estimate lock itself in.

    Returns a ModeFit, or None if the candidate did not decay like a mode. Returning None is
    the point: a mains hum and a logging artefact both make a fine spectral peak and neither
    is a structural mode, and the R^2 gate is what tells them apart.
    """
    half = max(BANDPASS_MIN_HALF_HZ, BANDPASS_HALF_FRACTION * centre_hz)
    first = _fit_at_bandwidth(window, fs, centre_hz, half, prominence)
    if first is None:
        return None
    matched = max(half, BANDPASS_HALF_WIDTHS * first.zeta * first.hz)
    fit = _fit_at_bandwidth(window, fs, centre_hz, matched, prominence) if matched > half else first
    if fit is None or fit.r2 < MIN_DECAY_R2:
        return None
    return fit


def analyse_strike(x, fs, onset):
    """Candidates from BOTH pre-registered detection windows; every fit on the long one.

    TWO WINDOW LENGTHS, and the reason is the same physics that killed the Hann window. How
    long a ringdown lasts depends on the mode: at 143 Hz and zeta = 0.03 it rings for 100 ms
    and needs a long frame to be resolved from its neighbours, while at 420 Hz and zeta = 0.05
    it is finished in 20 ms and a long frame buries it under 230 ms of integrated noise. One
    fixed length cannot see both, and DETECTION_WINDOWS_S is set to a short and a long rather
    than to a compromise that sees neither well. Detection takes the UNION; the fit always runs
    on the long window, since fit_mode only uses samples down to ENV_FLOOR_RATIO of the
    envelope peak and simply ignores the rest.
    """
    blank = int(round(BLANK_S * fs))
    start = onset + blank
    length = int(round(ANALYSIS_WINDOW_S * fs))
    window = x[start:start + length]
    if len(window) < length // 2:
        return []
    window = window - window.mean()

    candidates = []
    for seconds in DETECTION_WINDOWS_S:
        short = window[:int(round(seconds * fs))]
        if len(short) < 64:
            continue
        for centre, prom in candidate_peaks(short - short.mean(), fs):
            if any(abs(centre - c) < PEAK_MERGE_FRACTION * c for c, _ in candidates):
                continue
            candidates.append((centre, prom))

    fits = []
    for centre, prom in sorted(candidates):
        fit = fit_mode(window, fs, centre, prom)
        if fit is not None:
            fits.append(fit)
    return fits


# ---------------------------------------------------------------------------
# Combining strikes
# ---------------------------------------------------------------------------


@dataclass
class ModeGroup:
    hz: float
    hz_spread: float
    zeta: float
    zeta_spread: float
    prominence: float
    amplitude: float
    strikes: int
    of_strikes: int

    def matches(self, hz, tol=GROUP_TOLERANCE):
        return abs(self.hz - hz) <= tol * hz


def combine(per_strike):
    """Group candidates across strikes; keep those that recurred. See pre-registration 4."""
    n_strikes = len(per_strike)
    flat = [(i, f) for i, fits in enumerate(per_strike) for f in fits]
    groups, used = [], set()
    for idx, (i, fit) in enumerate(flat):
        if idx in used:
            continue
        members = [(i, fit)]
        used.add(idx)
        for jdx, (j, other) in enumerate(flat):
            if jdx in used:
                continue
            if abs(other.hz - fit.hz) <= GROUP_TOLERANCE * fit.hz:
                members.append((j, other))
                used.add(jdx)
        strikes_seen = len({m[0] for m in members})
        if n_strikes and strikes_seen < math.ceil(MIN_STRIKE_FRACTION * n_strikes):
            continue
        hz = np.array([m[1].hz for m in members])
        zt = np.array([m[1].zeta for m in members])
        groups.append(ModeGroup(
            hz=float(np.median(hz)),
            hz_spread=float(np.max(hz) - np.min(hz)) if len(hz) > 1 else 0.0,
            zeta=float(np.median(zt)),
            zeta_spread=float(np.max(zt) - np.min(zt)) if len(zt) > 1 else 0.0,
            prominence=float(np.median([m[1].prominence for m in members])),
            amplitude=float(np.median([m[1].amplitude for m in members])),
            strikes=strikes_seen,
            of_strikes=n_strikes,
        ))
    return sorted(groups, key=lambda g: g.hz)


def analyse(rec: Recording):
    """Every mode found in one recording, ascending in frequency."""
    onsets = find_strikes(rec.signal, rec.sample_rate_hz)
    if not onsets:
        return [], 0
    per_strike = [analyse_strike(rec.signal, rec.sample_rate_hz, o) for o in onsets]
    return combine(per_strike), len(onsets)


# ---------------------------------------------------------------------------
# The mode-identification rule. Pre-registration 2(v), implemented not eyeballed.
# ---------------------------------------------------------------------------


@dataclass
class Identification:
    hz: float | None
    zeta: float | None
    group: ModeGroup | None
    reasons: list
    checks_applied: list
    rejected: list


def expected_props_off_shift(tip_mass_with_prop_kg, prop_mass_kg):
    """f_off / f_on for removing the prop, by the sqrt mass law. Decision 2(iii)."""
    m_off = tip_mass_with_prop_kg - prop_mass_kg
    if m_off <= 0:
        raise ValueError("prop mass is not less than tip mass; check the weights")
    return math.sqrt(tip_mass_with_prop_kg / m_off)


def identify_first_bending(primary_by_arm, lateral=None, props_off=None,
                           expected_shift=None):
    """Apply the three pre-registered criteria and return the first candidate passing all.

    primary_by_arm : {arm label: [ModeGroup]} — vertical strike, the reference configuration.
    lateral        : [ModeGroup] from an in-plane strike on any one arm, or None.
    props_off      : [ModeGroup] from the same arm with the prop removed, or None.
    expected_shift : f_off / f_on predicted by the mass law, from expected_props_off_shift.

    A criterion whose configuration was not recorded is reported as NOT APPLIED rather than
    silently passed. A result identified on fewer than three criteria is weaker evidence and
    the report says so; it does not quietly become the same claim.
    """
    checks = ["(a) four-arm consistency"]
    if lateral is not None:
        checks.append("(b) directional")
    if props_off is not None and expected_shift is not None:
        checks.append("(c) tip-mass sensitive")

    arms = sorted(primary_by_arm)
    if not arms:
        return Identification(None, None, None, ["no primary recordings"], checks, [])
    reference_arm = arms[0]
    rejected = []

    for cand in sorted(primary_by_arm[reference_arm], key=lambda g: g.hz):
        why = []

        # (a) present on every arm struck, within ARM_CONSISTENCY_FRACTION
        seen_on = []
        for arm in arms:
            hit = next((g for g in primary_by_arm[arm]
                        if abs(g.hz - cand.hz) <= ARM_CONSISTENCY_FRACTION * cand.hz), None)
            if hit is None:
                why.append(f"(a) absent on arm {arm}")
                break
            seen_on.append(hit)
        if why:
            rejected.append((cand.hz, why[0]))
            continue

        # (b) excited far harder by a vertical strike than an in-plane one
        if lateral is not None:
            twin = next((g for g in lateral
                         if abs(g.hz - cand.hz) <= ARM_CONSISTENCY_FRACTION * cand.hz), None)
            lateral_amp = twin.amplitude if twin is not None else 0.0
            if lateral_amp > 0 and cand.amplitude < DIRECTION_RATIO * lateral_amp:
                rejected.append((cand.hz,
                                 f"(b) vertical/lateral amplitude is "
                                 f"{cand.amplitude / lateral_amp:.1f}x, under {DIRECTION_RATIO}x"))
                continue

        # (c) moves by the mass law when the prop comes off
        if props_off is not None and expected_shift is not None:
            want = cand.hz * expected_shift
            twin = next((g for g in props_off
                         if abs(g.hz - want) <= TIP_MASS_SHIFT_TOLERANCE * want), None)
            if twin is None:
                nearest = min((abs(g.hz - want), g.hz) for g in props_off) if props_off else (0, 0)
                rejected.append((cand.hz,
                                 f"(c) expected {want:.1f} Hz with the prop off "
                                 f"(x{expected_shift:.3f}); nearest found {nearest[1]:.1f} Hz"))
                continue

        agreement = max(abs(g.hz - cand.hz) / cand.hz for g in seen_on)
        return Identification(
            hz=float(np.median([g.hz for g in seen_on])),
            zeta=float(np.median([g.zeta for g in seen_on])),
            group=cand,
            reasons=[f"lowest candidate passing every applied criterion; "
                     f"arms agree to {agreement:.1%}"],
            checks_applied=checks,
            rejected=rejected,
        )

    return Identification(None, None, None,
                          ["no candidate satisfied every applied criterion"], checks, rejected)


# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------


def report(ident: Identification, arm_m: float, tip_mass_kg: float, props_on: bool = True,
           shift_applied: float | None = None) -> bool:
    modelled = resonance_hz_for(arm_m, tip_mass_kg)

    print(f"\n  build            : arm {arm_m*1000:.1f} mm, tip mass {tip_mass_kg*1000:.1f} g "
          f"({'props on' if props_on else 'props off'})")
    print(f"  criteria applied : {', '.join(ident.checks_applied)}")
    for hz, why in ident.rejected:
        print(f"  rejected {hz:7.1f} Hz : {why}")

    if ident.hz is None:
        print(f"  NO MODE IDENTIFIED: {ident.reasons[0]}.")
        print("  This is a valid outcome. It is not evidence that the frame has no mode, and it")
        print("  is not a disagreement with the model. Nothing downstream may be changed on it.")
        return False

    measured = ident.hz
    note = ""
    if shift_applied is not None:
        measured = ident.hz / shift_applied
        note = (f"  (measured {ident.hz:.1f} Hz with the prop off, converted by "
                f"/{shift_applied:.3f} — decision 2(iii))")

    error = (measured - modelled) / modelled
    print(f"  identified       : {ident.reasons[0]}")
    print(f"  measured f       : {measured:.1f} Hz{note and chr(10) + note or ''}")
    print(f"  modelled f       : {modelled:.1f} Hz")
    print(f"  error            : {error:+.1%}  against a pre-registered +-{IMPACT_AGREEMENT_FRACTION:.0%}")
    print(f"  measured zeta    : {ident.zeta:.4f}  (Q = {1.0/(2.0*ident.zeta):.0f})")
    zeta_ratio = ident.zeta / DEFAULT_DAMPING_RATIO
    print(f"  modelled zeta    : {DEFAULT_DAMPING_RATIO:.4f}  -> ratio {zeta_ratio:.2f}x "
          f"against a pre-registered factor of {DAMPING_AGREEMENT_FACTOR:.0f}")

    f_ok = abs(error) <= IMPACT_AGREEMENT_FRACTION
    z_ok = (1.0 / DAMPING_AGREEMENT_FACTOR) <= zeta_ratio <= DAMPING_AGREEMENT_FACTOR
    print(f"  verdict f        : {'WITHIN BOUND' if f_ok else 'OUTSIDE BOUND'}")
    print(f"  verdict zeta     : {'WITHIN BOUND' if z_ok else 'OUTSIDE BOUND'}")
    if not f_ok:
        print("  The bound is NOT widened and REFERENCE_RESONANCE_HZ is NOT retuned to this "
              "number.\n  Report the disagreement; that is the finding.")
    if abs(error) <= 0.12:
        print("  NOTE: this is inside 12%, which the bound cannot resolve — see section 1. A pass "
              "here\n  does not distinguish 180 Hz from the 160 Hz that flips the reference build "
              "to D-limited.")
    return f_ok and z_ok


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("recordings", nargs="+",
                    help="one file per configuration, tagged: PATH:ARM:DIRECTION:PROPS  e.g. "
                         "arm_a.wav:A:vertical:on")
    ap.add_argument("--source", choices=("wav", "betaflight", "lothal"), required=True)
    ap.add_argument("--arm-mm", type=float, required=True, help="hub face to motor shaft centre")
    ap.add_argument("--tip-mass-g", type=float, required=True, help="motor + hardware + prop, weighed")
    ap.add_argument("--prop-mass-g", type=float, required=True, help="one prop, weighed")
    ap.add_argument("--axis", default="roll", choices=("roll", "pitch"), help="gyro sources only")
    args = ap.parse_args(argv)

    loaders = {"wav": load_wav, "betaflight": load_betaflight_impact, "lothal": load_lothal_impact}
    load = loaders[args.source]

    primary, lateral, props_off = {}, None, None
    for spec in args.recordings:
        parts = spec.split(":")
        path, arm = parts[0], (parts[1] if len(parts) > 1 else "A")
        direction = parts[2] if len(parts) > 2 else "vertical"
        props = (parts[3] if len(parts) > 3 else "on") == "on"
        meta = dict(arm=arm, direction=direction, props=props)
        rec = load(path, **meta) if args.source == "wav" else load(path, axis=args.axis, **meta)
        assert_usable(rec)
        groups, strikes = analyse(rec)
        print(f"{os.path.basename(path):32s} arm {arm} {direction:8s} "
              f"props {'on ' if props else 'off'} : {strikes} strikes, "
              f"{len(groups)} recurring modes  [{rec.unfiltered_evidence}]")
        print(f"{'':32s}   [{rec.sampling_evidence}]")
        for g in groups:
            print(f"    {g.hz:7.1f} Hz  zeta {g.zeta:.4f}  prom {g.prominence:4.1f}x  "
                  f"seen in {g.strikes}/{g.of_strikes} strikes  spread {g.hz_spread:.1f} Hz")
        if direction == "lateral":
            lateral = groups
        elif not props:
            props_off = groups
        else:
            primary[arm] = groups

    tip_kg = args.tip_mass_g / 1000.0
    shift = expected_props_off_shift(tip_kg, args.prop_mass_g / 1000.0)

    # The gyro route records props off, so the primary set may BE the props-off set.
    shift_applied = None
    if not primary and props_off is not None:
        primary = {"A": props_off}
        props_off = None
        shift_applied = shift

    ident = identify_first_bending(primary, lateral=lateral, props_off=props_off,
                                   expected_shift=shift)
    ok = report(ident, args.arm_mm / 1000.0, tip_kg, props_on=shift_applied is None,
                shift_applied=shift_applied)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
