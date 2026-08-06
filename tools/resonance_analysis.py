#!/usr/bin/env python3
"""Measure a frame's first bending mode from a gyro trace, and check 180 Hz (LTHL-18).

===========================================================================
WHAT THIS IS FOR
===========================================================================

VibrationModel.REFERENCE_RESONANCE_HZ is 180.0 and its own comment says "No source. There is
no source." Every frame in data/parts/frames.json rings at a ratio to that one number through
the tip-loaded cantilever scaling law, and because the anchor cannot be checked,
RateTune.kd_ceiling_for refuses to let vibration move the D gains at all — which leaves six of
fourteen frames sitting on the wrong side of a 2% noise budget with nothing done about it.

This file answers one question: is 180 Hz right?

It reads a gyro trace — either a real Betaflight blackbox log or a Lothal FlightRecorder log,
through the SAME code path below the loader — finds the throttle-invariant spectral feature,
and compares it to VibrationModel.resonance_hz_for() for the matching build.

Analysis is here and not in Godot for the reason flight_recorder.gd gives: numpy.fft already
exists and is better than anything a half-built spectrum viewer in GDScript would be.

===========================================================================
PRE-REGISTRATION. WRITTEN AND COMMITTED BEFORE ANY DATA WAS LOOKED AT.
===========================================================================

This is the methodological content of the slice, and it is the same discipline
ThrustValidation and BuildValidation were given: the bound is fixed in advance, so the git
history shows it was chosen blind. A bound moved to fit the data it measures is not a bound.
If the measurement busts AGREEMENT_FRACTION, that is reported and diagnosed. It is not
widened, and REFERENCE_RESONANCE_HZ is not retuned to whatever came out — that would convert
a measurement into a fit and destroy the only thing this slice earns.

---------------------------------------------------------------------------
1. THE BOUND: 25%, and why it is so much wider than a thrust measurement's
---------------------------------------------------------------------------

BuildValidation gets 5% because it validates an ADDITION of published masses. ThrustValidation
gets 10-20% because it interpolates rules of thumb across propeller geometry. This gets 25%,
and the extra width is not generosity — it is that a frame's first bending mode is genuinely
not a single number per product. It is a property of a BUILD: of how hard the arm bolts were
done up, of whether the arms carry TPU, of what else is cable-tied to them.

Decomposed, in quadrature, each term as its effect on frequency:

  * Root fixity — arm bolt torque, plate stiffness, whether the arm is clamped between two
    plates or bolted to one.  +-10%.  The largest single term and the least reducible, because
    a real cantilever root is somewhere between clamped and pinned and moves with a hex key.
  * Arm length definition.  +-5% in L, and f goes as L^-1.5, so  +-7.5%.  110 mm measured to
    the motor shaft centre is not 110 mm measured to the end of the arm, and frames.json's
    arm_m is a published figure whose convention the manufacturer does not state.
  * The dropped arm-mass term.  vibration_model.gd drops (33/140)*m_arm from the effective
    mass, which is a 7% correction on the reference build and varies down the catalog.
    Call it 5% of transport error between two different frames.
  * Unpublished tip mass — mounting hardware, motor wires, a TPU antenna mount, an ND filter
    holder.  Plausibly +10% on tip mass, one-sided, and f goes as m^-0.5, so  -5%.
  * Peak-picking itself.  At DEFAULT_DAMPING_RATIO = 0.03 the half-power bandwidth is
    2*zeta = 6% of f_n, so a peak read off a spectrum is worth about  +-3%.

sqrt(10^2 + 7.5^2 + 5^2 + 5^2 + 3^2) = 14.7%, call it 15% for one standard deviation. The
bound is set at 25%, which is about 1.7 sigma — tight enough that a wrong anchor fails it
(160 Hz against 180 Hz is 11%, and would PASS, which is stated plainly because it means this
measurement cannot settle the 12% question kd_ceiling_for's comment raises; it can only catch
an anchor that is wrong by more than a build's own spread), and loose enough that a genuinely
correct model is not failed by a pilot's bolt torque.
"""

AGREEMENT_FRACTION = 0.25

"""
---------------------------------------------------------------------------
2. WHAT MAKES A LOG ADMISSIBLE. All four required, checked before analysis.
---------------------------------------------------------------------------

  a. UNFILTERED GYRO. This is the trap that decides the whole slice. Betaflight's default
     blackbox `gyroADC[]` is logged AFTER the gyro lowpass, which attenuates exactly the peak
     being hunted. A filtered log shows a suppressed or absent peak and the conclusion drawn
     from it would be that the model is wrong when in fact the data is. Admissible sources
     are `debug_mode = GYRO_SCALED` (debug[0..2] carry pre-filter gyro), or a log flown with
     gyro_lowpass_type = OFF / gyro_lowpass_hz = 0. assert_unfiltered() below refuses
     anything else, and refusing is the intended behaviour, not an obstacle to route around.
  b. A NAMED FRAME, specific enough to look up an arm length for. Inventing an arm length to
     make a log usable would poison the result exactly as inventing a mass would have poisoned
     data/validation/builds.json.
  c. NAMED MOTORS AND PROPS, because tip mass is half the scaling law.
  d. A SLOW THROTTLE SWEEP. This was pre-registered as "a throttle sweep or varied flight, not
     a static hover, because the discriminator needs the harmonics to move" — and that turned
     out to be badly underspecified in a way only real data revealed. The harmonics must move
     SLOWLY: a harmonic has to be a LINE within one analysis frame for its magnitude to be
     readable at all.

     Measured on four real Betaflight logs from one freestyle session, the 1x line moves by a
     median of 155-235 Hz WITHIN a single 1.024 s frame — 160 to 240 FFT bins. At that rate
     the harmonic is not a line, it is a smear across half the band, and there is nothing for
     order tracking to ride. Normal flying is therefore USELESS for this measurement no matter
     how varied it is, and "varied flight" as an alternative to a sweep was simply wrong.

     What is needed is a deliberate slow sweep, of the kind tools/record_sweep.gd flies: about
     7 Hz/s of 1x drift rather than 200. That is a much heavier ask of a pilot than the
     original wording implied, and it is the single most important thing to put in the request
     if a log is ever commissioned rather than found. NOTE the direction this moved: it made
     admissibility STRICTER after the data, never looser, and AGREEMENT_FRACTION was untouched.
  e. LOGGED RPM. Added when the statistic changed in section 3 and it is a real narrowing:
     order tracking needs to know where each harmonic WAS in each frame, and a throttle
     percentage does not say that. In Betaflight that means bidirectional DShot with
     eRPM[0..3] in the log; a log without it is inadmissible here even though it would have
     been admissible under the first statistic. Lothal's recorder logs m*_rpm always.

---------------------------------------------------------------------------
3. THE DISCRIMINATOR: ride the harmonic, and watch it get louder
---------------------------------------------------------------------------

A gyro spectrum holds rpm-driven lines (rotation, blade passage, and their harmonics) and
structural modes, and telling them apart is the entire problem. A single FFT cannot: it sums
a swept line and a fixed mode into the same picture.

A NOTE ON WHAT THIS SECTION FIRST SAID, because the git history shows it changing and the
reason matters more than the result. The first pre-registered statistic here was the
THROTTLE-MEDIAN SPECTRUM: median rather than mean across spectrogram frames, on the reasoning
that a swept harmonic visits a bin briefly and is rejected while a fixed mode is present in
every frame and survives. It was committed, then run against synthetic data with a mode
planted at a known frequency — and it failed, returning 495 Hz for a mode planted at 143 Hz,
and returning an equally confident answer from a control trace with no mode in it at all.

The reason it failed is the physically interesting part. A frame mode is not "present in
every frame". IT IS ONLY VISIBLE WHILE SOMETHING IS EXCITING IT. In the synthetic sweep the
planted mode carried energy in 11% of frames and nothing in the other 89%, so the median
threw the resonance away along with the harmonics. That would have been just as true of a
real log. The statistic was rejecting exactly what it was built to find.

This was changed BEFORE any real log was read — the failure came from synthetic data with a
known answer, which is what synthetic data is for. AGREEMENT_FRACTION was not touched.

So the statistic is ORDER TRACKING, which uses the brightening as the signal instead of
treating it as a side-check:

  For each spectrogram frame we know the rotation frequency, because rpm is logged. Read the
  magnitude at k x rotation for each order k — the 1x imbalance line, the blade-pass line,
  and their overtones — and plot it against the frequency that line was AT in that frame.
  As the sweep carries a harmonic up through the mode, that curve traces out the structure's
  magnitude response directly. Its peak is the resonance.

This is swept-sine testing, done with the aircraft's own props as the shaker. It inverts the
problem: instead of trying to see a fixed feature through moving lines, it follows the moving
lines and reads off where they got loud. And it discriminates for free — a fixed EXCITATION
(an ESC artefact, a logging-rate line) never appears in the order curve at all, because the
order curve only ever samples frequencies a harmonic was actually sitting on.

TREND REMOVAL, and why it is not a physical model. Forcing amplitude itself grows with rpm —
an imbalance force goes as omega^2 — so the raw order curve rises whether or not anything
resonates. Dividing by an assumed omega^2 would import the forcing model into the
measurement and shift the apparent peak. Instead a SMOOTH TREND is estimated from the order
curve itself, as a running median in frequency, and divided out. That is assumption-light and
works because a resonance at zeta = 0.03 is narrow (6% half-power bandwidth) against any
smooth forcing law, whatever its exponent.

---------------------------------------------------------------------------
4. PRE-REGISTERED ANALYSIS PARAMETERS
---------------------------------------------------------------------------

Fixed here so the analysis is reproducible and so no parameter can be nudged after seeing a
spectrum. Window and overlap change apparent peak width, which is exactly why they are
written down rather than chosen per-log.

  * Window: Hann.
  * Frame length: EQUAL FREQUENCY RESOLUTION, NOT EQUAL SAMPLE COUNT. Every log is framed at
    FRAME_SECONDS = 1.024 s regardless of its sample rate, so a 1 kHz Lothal log and an 8 kHz
    blackbox log are compared at the same ~0.98 Hz bin width. Framing both at 1024 SAMPLES
    would give the blackbox log eight times the resolution and a visibly narrower peak, and
    the comparison would be measuring the analysis rather than the model.
  * Overlap: 75%.
  * Detrend: per-frame mean removal only. No highpass, no windowed pre-filtering — filtering
    the trace is the thing this whole file exists to avoid.
  * Orders tracked: 1x (prop imbalance), and the blade-pass line at blades x 1x, and 2x. Three
    orders, because more sweeps of the same structure sample its response at more frequencies
    and all three must agree on where the peak is.
  * Search band: SEARCH_BAND_HZ = (60, 600). Below 60 Hz is rigid-body motion and the pilot's
    own stick inputs; above 600 Hz is beyond the first bending mode of any 3-10" arm and into
    motor bell and ESC territory. The band is fixed for every log.
  * Order-curve grid: the tracked orders are resampled onto ORDER_GRID_HZ = 2.0 Hz bins by
    median within bin, so a slow sweep that lingers cannot outvote a fast one.
  * Detection floor: MIN_PROMINENCE = 1.5x the trend. Below it, the answer is "no resonance
    found in this log", not a frequency. Calibrated on synthetic traces containing NO mode at
    all, where the rule's best peak came back at 1.00-1.04x, against 4-6x for planted modes.
    The floor sits in that gap, nearer the noise end. Without it the rule always returns a
    number, and a number is not the same thing as a detection.
  * Peak rule: the GLOBAL MAXIMUM of the trend-divided order curve inside the search band.
    Which peak was selected, and what the runners-up were, are both printed — if two
    candidates are within AMBIGUITY_RATIO the result is reported as ambiguous rather than
    resolved by picking one.
  * COVERAGE IS A PRECONDITION, NOT A RESULT. The order curve only exists at frequencies some
    harmonic actually visited. If the harmonics never swept across the modelled resonance,
    the log cannot say anything about it and is reported as inconclusive rather than as a
    disagreement — a peak found at the edge of the swept range is an artefact of where the
    sweep stopped. MIN_COVERAGE_SPAN is the required width of swept range around the
    modelled frequency, and it is set to the pre-registered bound itself: a log that cannot
    see +-25% around the model cannot test the +-25% claim.
  * Axis: roll and pitch are analysed and reported separately, never averaged. An arm bending
    mode couples to both, and if they disagree that is information.

---------------------------------------------------------------------------
5. UNITS
---------------------------------------------------------------------------

Betaflight blackbox is deg/s. Lothal is rad/s throughout, and flight_recorder.gd deliberately
does not convert on the way out. The one conversion happens in load_lothal(), visibly, and
every spectrum below this line is in deg/s. Frequency is unaffected by the scale factor, so
this cannot move the answer — it is done anyway so the two magnitude plots can be laid on the
same axis and so the next reader does not have to wonder.
"""

FRAME_SECONDS = 1.024
OVERLAP_FRACTION = 0.75
SEARCH_BAND_HZ = (60.0, 600.0)
ORDER_GRID_HZ = 2.0
TREND_MEDIAN_BINS = 51
AMBIGUITY_RATIO = 0.8
MIN_PROMINENCE = 1.5
MIN_COVERAGE_SPAN = AGREEMENT_FRACTION

RAD_TO_DEG = 57.29577951308232

import argparse
import json
import math
import sys
from dataclasses import dataclass, field

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    sys.exit("numpy is required: python3 -m venv .venv && .venv/bin/pip install numpy")


# ---------------------------------------------------------------------------
# The model under test, transcribed from src/sim/vibration_model.gd
# ---------------------------------------------------------------------------
#
# Transcribed rather than imported because Godot is not on the path of a Python process, and
# kept to the three constants and one function so the transcription is checkable by eye.
# tests/test_vibration.gd holds the authoritative version; if these drift, that test is right
# and this file is wrong.

REFERENCE_RESONANCE_HZ = 180.0
REFERENCE_ARM_M = 0.110
REFERENCE_TIP_MASS_KG = 0.0365
ARM_LENGTH_EXPONENT = 1.5


def resonance_hz_for(arm_m: float, tip_mass_kg: float) -> float:
    """The frame's first arm-bending mode. Mirrors VibrationModel.resonance_hz_for."""
    if arm_m <= 0.0 or tip_mass_kg <= 0.0:
        return REFERENCE_RESONANCE_HZ
    return (
        REFERENCE_RESONANCE_HZ
        * (REFERENCE_ARM_M / arm_m) ** ARM_LENGTH_EXPONENT
        * math.sqrt(REFERENCE_TIP_MASS_KG / tip_mass_kg)
    )


# ---------------------------------------------------------------------------
# Loading
# ---------------------------------------------------------------------------


@dataclass
class Trace:
    """A gyro trace, whatever produced it. Everything below this is source-blind."""

    name: str
    source: str  # "betaflight" | "lothal"
    sample_rate_hz: float
    roll_deg_s: "np.ndarray"
    pitch_deg_s: "np.ndarray"
    #: Mechanical rotation frequency of the props, shape (samples, motors). Order tracking
    #: needs an actual frequency, not a throttle percentage — see pre-registration 2e.
    #:
    #: PER MOTOR, NOT AVERAGED, and this was a real defect found on real data. Averaging the
    #: four eRPM channels and tracking one nominal 1x line smears the harmonic, because in
    #: flight the four motors genuinely run at different rpm — that difference IS the roll and
    #: pitch command. Checking the tracked 1x against the gyro's own dominant line put the
    #: ratio's mode at 0.875 rather than 1.0 with a long tail, which is the smear. Each motor
    #: is tracked on its own eRPM instead, which is also the physically right thing: each arm
    #: is a separate cantilever with its own shaker bolted to the end of it.
    rot_hz: "np.ndarray"
    blades: int
    unfiltered: bool
    unfiltered_evidence: str
    header: dict = field(default_factory=dict)


def load_lothal(path: str, blades: int) -> Trace:
    """A FlightRecorder log: one '#'-commented JSON header line, then CSV.

    Lothal's gyro_* columns are the SENSOR estimate — the channel the flight controller was
    actually handed, which is what a blackbox log records too. omega_* is ground truth and is
    deliberately not used: comparing Lothal's ground truth against a real aircraft's sensor
    would compare two different quantities and flatter or damn the model for the wrong reason.
    """
    # The JSON header is pretty-printed across SEVERAL '#' lines, not one — the same shape
    # tests/test_flight_recorder.gd's _header() reads. Stripping one '#' per line and
    # concatenating is the whole decode.
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
    rpm = np.column_stack([rows[:, col[f"m{i}_rpm"]] for i in (1, 2, 3, 4)])
    return Trace(
        name=header.get("aircraft", {}).get("fingerprint", path),
        source="lothal",
        sample_rate_hz=float(header.get("sample_rate_hz", 1000.0)),
        # THE one unit conversion. rad/s in the file, deg/s from here on.
        roll_deg_s=rows[:, col["gyro_x_rad_s"]] * RAD_TO_DEG,
        pitch_deg_s=rows[:, col["gyro_z_rad_s"]] * RAD_TO_DEG,
        rot_hz=rpm / 60.0,
        blades=blades,
        # Lothal's Gyro applies its own lowpass; a log flown with it disabled is the
        # comparable one. The header records the cutoff, so this is checked, not assumed.
        unfiltered=_lothal_unfiltered(header),
        unfiltered_evidence=f"header gyro lowpass: {header.get('gyro', {}).get('lowpass_hz', 'absent')}",
        header=header,
    )


def _lothal_unfiltered(header: dict) -> bool:
    lp = header.get("gyro", {}).get("lowpass_hz")
    return lp is None or float(lp) <= 0.0 or float(lp) >= 500.0


#: Blackbox field names that carry PRE-filter gyro. debug[] only when debug_mode is one of
#: GYRO_SCALED / GYRO_RAW — the CSV column names are identical whatever debug_mode was set to,
#: which is exactly how a filtered log gets mistaken for an unfiltered one.
PREFILTER_DEBUG_MODES = {"GYRO_SCALED", "GYRO_RAW", "GYRO_SAMPLE"}


def load_betaflight(path: str, arm_m: float, tip_mass_kg: float, blades: int, pole_pairs: int) -> Trace:
    """A blackbox log already decoded to CSV by `blackbox_decode`.

    Frame, motor and prop are NOT in the log — Betaflight does not record what the aircraft is
    made of — so arm_m and tip_mass_kg are passed in from the pilot's own build description and
    must be cited alongside any result. This is the same rule data/validation/builds.json ships
    under: a number nobody published does not get invented to make the analysis run.
    """
    header, names, rows = _read_bbl_csv(path)
    col = {n: i for i, n in enumerate(names)}

    unfiltered, evidence, roll_key, pitch_key = _choose_gyro_columns(header, col)

    t_us = rows[:, col["time (us)"]] if "time (us)" in col else rows[:, 0]
    dt = np.median(np.diff(t_us)) * 1e-6

    # Bidirectional DShot only. eRPM is ELECTRICAL rpm; mechanical is eRPM / pole_pairs, and
    # blackbox scales it by 100. Getting this factor wrong scales every measured frequency by
    # an integer, which is the second easiest way to ruin this comparison after deg/s.
    erpm_keys = [k for k in ("eRPM[0]", "eRPM[1]", "eRPM[2]", "eRPM[3]") if k in col]
    if not erpm_keys:
        raise ValueError(
            f"{path}: no eRPM columns. Order tracking needs logged rpm (pre-registration 2e); "
            "this log was flown without bidirectional DShot and is inadmissible."
        )
    # The x100 is verified against the log itself rather than taken on trust: tracking the 1x
    # line at this scaling puts the gyro's own dominant line at a ratio of ~1, where the
    # x100/(2*pole_pairs) alternative would put it at ~1.8. See tools/ notes in the LTHL-18
    # write-up.
    erpm = np.column_stack([rows[:, col[k]] for k in erpm_keys])
    rot_hz = (erpm * 100.0 / pole_pairs) / 60.0

    return Trace(
        name=header.get("Craft name", path),
        source="betaflight",
        sample_rate_hz=1.0 / dt,
        roll_deg_s=rows[:, col[roll_key]],
        pitch_deg_s=rows[:, col[pitch_key]],
        rot_hz=rot_hz,
        blades=blades,
        unfiltered=unfiltered,
        unfiltered_evidence=evidence,
        header=dict(header, arm_m=arm_m, tip_mass_kg=tip_mass_kg),
    )


def _choose_gyro_columns(header, col):
    """Decide whether this log's gyro is pre-filter, and say on what evidence.

    Returns (unfiltered, evidence, roll_key, pitch_key). The evidence string is printed with
    every result, because "the peak was at 180 Hz" means nothing without "and the gyro was
    logged before the lowpass".
    """
    debug_mode = str(header.get("debug_mode", "")).strip().upper()
    if debug_mode in PREFILTER_DEBUG_MODES and "debug[0]" in col:
        return True, f"debug_mode = {debug_mode}; using debug[0..1]", "debug[0]", "debug[1]"

    lp_type = str(header.get("gyro_lowpass_type", "")).strip().upper()
    lp_hz = header.get("gyro_lowpass_hz", header.get("gyro_lowpass_hz_roll"))
    lp_off = lp_type in ("OFF", "NONE", "0") or (lp_hz is not None and float(lp_hz) == 0)
    if lp_off and "gyroADC[0]" in col:
        return (
            True,
            f"gyro_lowpass_type = {lp_type or 'unset'}, gyro_lowpass_hz = {lp_hz}; using gyroADC[0..1]",
            "gyroADC[0]",
            "gyroADC[1]",
        )

    return (
        False,
        f"gyroADC is POST-filter (debug_mode = {debug_mode or 'unset'}, "
        f"gyro_lowpass_type = {lp_type or 'unset'}, gyro_lowpass_hz = {lp_hz})",
        "gyroADC[0]",
        "gyroADC[1]",
    )


def _read_bbl_csv(path: str):
    """blackbox_decode writes 'H key,value' header lines, then a CSV header, then rows."""
    header, names = {}, None
    data = []
    with open(path) as fh:
        for line in fh:
            if line.startswith('"'):
                if names is None:
                    names = [c.strip().strip('"') for c in line.split(",")]
                    continue
            if names is None:
                if "," in line:
                    k, _, v = line.partition(",")
                    header[k.strip().lstrip("H ").strip()] = v.strip()
                continue
            data.append(line)
    if names is None:
        raise ValueError(f"{path}: no CSV header row found")
    return header, names, np.loadtxt(data, delimiter=",")


def assert_unfiltered(trace: Trace) -> None:
    """Refuse a filtered log, loudly. See pre-registration section 2a."""
    if trace.unfiltered:
        return
    sys.exit(
        f"REFUSED: {trace.name} ({trace.source}) has FILTERED gyro data.\n"
        f"  {trace.unfiltered_evidence}\n"
        "A gyro lowpass attenuates exactly the peak this analysis hunts, so a result from this\n"
        "log would say the model is wrong when the data is. Re-log with debug_mode = GYRO_SCALED."
    )


# ---------------------------------------------------------------------------
# The analysis. One code path, both sources.
# ---------------------------------------------------------------------------


def spectrogram(x, fs):
    """Hann-windowed magnitude spectrogram at the pre-registered frame length and overlap.

    Returns (freqs, frame_start_times, magnitudes[frame, bin]).
    """
    n = int(round(FRAME_SECONDS * fs))
    step = max(1, int(round(n * (1.0 - OVERLAP_FRACTION))))
    if len(x) < n:
        raise ValueError(f"trace is {len(x)/fs:.2f} s, shorter than one {FRAME_SECONDS} s frame")
    window = np.hanning(n)
    starts = np.arange(0, len(x) - n + 1, step)
    frames = np.array([np.abs(np.fft.rfft((x[s:s + n] - x[s:s + n].mean()) * window)) for s in starts])
    freqs = np.fft.rfftfreq(n, 1.0 / fs)
    return freqs, starts / fs, frames


def frame_rot_hz(rot_hz, fs, frame_count):
    """Mean rotation frequency within each spectrogram frame, per motor.

    Accepts (samples,) or (samples, motors) and returns (frames,) or (frames, motors).
    """
    n = int(round(FRAME_SECONDS * fs))
    step = max(1, int(round(n * (1.0 - OVERLAP_FRACTION))))
    return np.array([np.mean(rot_hz[i * step:i * step + n], axis=0) for i in range(frame_count)])


def order_samples(freqs, frames, rot_per_frame, order):
    """Ride ONE harmonic and read its magnitude — the statistic from pre-registration 3.

    Returns (frequency, magnitude) pairs, one per frame, the frequency being where that
    harmonic sat in that frame. Magnitude is the LOCAL MAXIMUM within +-2 bins of the
    predicted line, because rpm wanders slightly inside a 1 s frame and a hard bin lookup
    would read the shoulder of the line rather than the line.
    """
    df = freqs[1] - freqs[0]
    f_out, mag_out = [], []
    for frame_i, rot in enumerate(rot_per_frame):
        f = order * rot
        if not (SEARCH_BAND_HZ[0] <= f <= SEARCH_BAND_HZ[1]) or f >= freqs[-1]:
            continue
        centre = int(round(f / df))
        lo, hi = max(0, centre - 2), min(len(freqs), centre + 3)
        f_out.append(f)
        mag_out.append(float(np.max(frames[frame_i, lo:hi])))
    return np.array(f_out), np.array(mag_out)


def _bin_to_grid(f_samples, mag_samples, edges):
    """Median within each pre-registered bin, so a slow sweep cannot outvote a fast one."""
    idx = np.digitize(f_samples, edges) - 1
    out = np.full(len(edges) - 1, np.nan)
    for b in range(len(edges) - 1):
        sel = mag_samples[idx == b]
        if len(sel):
            out[b] = np.median(sel)
    return out


def order_curve(freqs, frames, rot_per_frame, orders):
    """The measured magnitude response: every order trend-divided SEPARATELY, then combined.

    EACH ORDER IS NORMALISED BEFORE THE ORDERS ARE MERGED, and this is not a detail. The 1x
    imbalance line, the 2x, and the blade-pass line all have different absolute amplitudes.
    Binning their raw magnitudes into one curve makes the curve STEP wherever the set of
    contributing orders changes — at 65 rps the 3x line arrives in a bin that previously held
    only 2x, and the median jumps for a reason that has nothing to do with the airframe.
    Synthetic traces with no resonance in them at all produced a confident 195 Hz "peak"
    exactly this way, which is how the bug was found and why this is written down.

    Normalising each order against its own smooth trend first removes its amplitude entirely,
    leaving only its SHAPE — how it rose and fell as it swept. Merging those is then merging
    like with like, and it strengthens the discriminator as a side effect: a real structural
    mode shows in every order that swept through it, at the same frequency, so the median
    across orders keeps it and rejects anything only one order saw.

    Returns (bin centres, combined ratio, all frequencies sampled by any order).
    """
    lo, hi = SEARCH_BAND_HZ
    edges = np.arange(lo, hi + ORDER_GRID_HZ, ORDER_GRID_HZ)
    centres = 0.5 * (edges[:-1] + edges[1:])

    rot_per_frame = np.atleast_2d(rot_per_frame.T).T  # (frames,) -> (frames, 1)
    motor_count = rot_per_frame.shape[1]

    per_order, all_f = [], []
    for motor in range(motor_count):
        for k in orders:
            f_s, m_s = order_samples(freqs, frames, rot_per_frame[:, motor], k)
            if len(f_s) == 0:
                continue
            all_f.append(f_s)
            binned = _bin_to_grid(f_s, m_s, edges)
            present = ~np.isnan(binned)
            if present.sum() < TREND_MEDIAN_BINS // 2:
                # Too few bins for this track to have a meaningful trend of its own; a trend
                # fitted to a handful of points is the resonance itself and would divide it out.
                continue
            ratio = np.full_like(binned, np.nan)
            y = binned[present]
            ratio[present] = y / np.maximum(_running_median(y, TREND_MEDIAN_BINS), 1e-30)
            per_order.append(ratio)

    if not per_order:
        return centres[:0], centres[:0], np.array([])

    stack = np.vstack(per_order)
    any_present = ~np.all(np.isnan(stack), axis=0)
    combined = np.full(stack.shape[1], np.nan)
    combined[any_present] = np.nanmedian(stack[:, any_present], axis=0)
    keep = ~np.isnan(combined)
    return centres[keep], combined[keep], np.concatenate(all_f) if all_f else np.array([])


def _running_median(y, k):
    k = min(k, len(y) | 1)
    half = k // 2
    padded = np.pad(y, half, mode="edge")
    return np.array([np.median(padded[i:i + k]) for i in range(len(y))])


@dataclass
class Peak:
    hz: float
    prominence: float  # magnitude relative to the smooth forcing trend


def pick_peak(f, ratio):
    """The pre-registered peak rule, on the already trend-divided order curve."""
    peaks, taken = [], []
    for i in np.argsort(ratio)[::-1]:
        # One peak per resonance: anything inside half a linewidth of an accepted peak is the
        # same feature's shoulder, not a second candidate. 6% is 2*zeta at DEFAULT_DAMPING_RATIO.
        if any(abs(f[i] - t) < 0.06 * t for t in taken):
            continue
        taken.append(f[i])
        peaks.append(Peak(hz=float(f[i]), prominence=float(ratio[i])))
        if len(peaks) == 4:
            break
    ambiguous = len(peaks) > 1 and peaks[1].prominence >= AMBIGUITY_RATIO * peaks[0].prominence
    return peaks[0], peaks[1:], ambiguous


def coverage(f_samples, modelled_hz):
    """Did the harmonics actually sweep across the frequency the model predicts?

    Pre-registration 4: a log whose sweep never reached the modelled resonance cannot test
    the claim, and a peak found at the edge of the swept range is an artefact of where the
    sweep stopped rather than a property of the airframe.
    """
    if len(f_samples) == 0:
        return False, (0.0, 0.0)
    lo, hi = float(np.min(f_samples)), float(np.max(f_samples))
    need_lo = modelled_hz * (1.0 - MIN_COVERAGE_SPAN)
    need_hi = modelled_hz * (1.0 + MIN_COVERAGE_SPAN)
    return (lo <= need_lo and hi >= need_hi), (lo, hi)


@dataclass
class Result:
    trace: Trace
    peak: Peak
    runners_up: list
    ambiguous: bool
    axis: str
    covered: bool
    swept_range: tuple
    sample_count: int


def analyse(trace: Trace, axis: str, modelled_hz: float) -> Result:
    x = trace.roll_deg_s if axis == "roll" else trace.pitch_deg_s
    freqs, _, frames = spectrogram(x, trace.sample_rate_hz)
    rot = frame_rot_hz(trace.rot_hz, trace.sample_rate_hz, len(frames))
    orders = sorted({1, 2, trace.blades})
    f, ratio, f_s = order_curve(freqs, frames, rot, orders)
    covered, swept = coverage(f_s, modelled_hz)
    if len(f) == 0:
        raise ValueError("no order swept enough of the band to be trended; is this a hover log?")
    peak, runners_up, ambiguous = pick_peak(f, ratio)
    return Result(
        trace=trace,
        peak=peak,
        runners_up=runners_up,
        ambiguous=ambiguous,
        axis=axis,
        covered=covered,
        swept_range=swept,
        sample_count=len(f_s),
    )


def report(result: Result, arm_m: float, tip_mass_kg: float) -> bool:
    """Prints the comparison and returns whether it fell inside the pre-registered bound."""
    modelled = resonance_hz_for(arm_m, tip_mass_kg)
    error = (result.peak.hz - modelled) / modelled

    print(f"\n{result.trace.name}  [{result.trace.source}, {result.axis}]")
    print(f"  gyro filtering : {result.trace.unfiltered_evidence}")
    print(f"  sample rate    : {result.trace.sample_rate_hz:.1f} Hz")
    print(f"  window         : Hann, {FRAME_SECONDS} s frames, {OVERLAP_FRACTION:.0%} overlap")
    print(f"  build          : arm {arm_m*1000:.0f} mm, tip mass {tip_mass_kg*1000:.1f} g")
    print(f"  orders swept   : {result.swept_range[0]:.0f}-{result.swept_range[1]:.0f} Hz "
          f"from {result.sample_count} harmonic samples")
    print(f"  measured peak  : {result.peak.hz:.1f} Hz  (prominence {result.peak.prominence:.2f}x trend)")
    print(f"  modelled       : {modelled:.1f} Hz")
    print(f"  error          : {error:+.1%}  against a pre-registered +-{AGREEMENT_FRACTION:.0%}")
    if result.runners_up:
        others = ", ".join(f"{p.hz:.1f} Hz ({p.prominence:.2f}x)" for p in result.runners_up)
        print(f"  runners-up     : {others}")
    if result.peak.prominence < MIN_PROMINENCE:
        print(f"  NO DETECTION: best peak is {result.peak.prominence:.2f}x trend, under the "
              f"{MIN_PROMINENCE}x floor. This log shows no resonance, which is not evidence "
              "that the frame has none.")
        return False
    if not result.covered:
        print(f"  INCONCLUSIVE: the harmonics never swept +-{MIN_COVERAGE_SPAN:.0%} either side of "
              f"{modelled:.1f} Hz, so this log cannot test the claim. Not a disagreement.")
        return False
    if result.ambiguous:
        print("  AMBIGUOUS: a second fixed feature is within "
              f"{AMBIGUITY_RATIO:.0%} of the selected one. Reported, not resolved.")
        return False
    verdict = "WITHIN BOUND" if abs(error) <= AGREEMENT_FRACTION else "OUTSIDE BOUND"
    print(f"  verdict        : {verdict}")
    return abs(error) <= AGREEMENT_FRACTION


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("log", help="a Lothal FlightRecorder CSV or a decoded blackbox CSV")
    ap.add_argument("--source", choices=("lothal", "betaflight"), required=True)
    ap.add_argument("--arm-mm", type=float, required=True, help="one arm, hub to motor centre")
    ap.add_argument("--tip-mass-g", type=float, required=True, help="motor + prop, one arm")
    ap.add_argument("--blades", type=int, default=3, help="blades per prop, for the blade-pass order")
    ap.add_argument("--pole-pairs", type=int, default=7,
                    help="motor pole pairs, betaflight only: eRPM is electrical")
    ap.add_argument("--allow-filtered", action="store_true",
                    help="analyse a filtered log anyway. The result is NOT admissible evidence "
                         "about the model; this exists only to demonstrate what filtering does.")
    args = ap.parse_args(argv)

    arm_m = args.arm_mm / 1000.0
    tip_mass_kg = args.tip_mass_g / 1000.0

    if args.source == "lothal":
        trace = load_lothal(args.log, args.blades)
    else:
        trace = load_betaflight(args.log, arm_m, tip_mass_kg, args.blades, args.pole_pairs)

    if not args.allow_filtered:
        assert_unfiltered(trace)
    elif not trace.unfiltered:
        print("WARNING: filtered gyro. Not admissible evidence about the model.")

    modelled = resonance_hz_for(arm_m, tip_mass_kg)
    ok = True
    for axis in ("roll", "pitch"):
        ok &= report(analyse(trace, axis, modelled), arm_m, tip_mass_kg)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
