#!/usr/bin/env python3
"""Find a frame mode in a CORPUS of logs that individually have no sweep (LTHL-50).

===========================================================================
WHAT THIS IS FOR, AND WHY IT IS NOT resonance_analysis.py
===========================================================================

LTHL-18's binding blocker is criterion (d), a slow throttle sweep. Every log ever examined has
failed it, in two opposite ways. Four freestyle logs failed because the 1x line moved 155-235
Hz WITHIN one 1.024 s analysis frame — 240 FFT bins of smear, no line to ride. The 141 INAV
logs (9be5b5a) fail because the throttle NEVER MOVES AT ALL: a survey platform sits at hover
+-6% for an entire flight, so there is one motionless line and nothing to separate it from a
mode by.

Both are the same missing thing. Order tracking needs the harmonics to MOVE relative to the
structure, and it needs to watch them move.

THE IDEA HERE: the corpus moves even though no log does. 141 flights of ONE aircraft, one
tune, unchanged config, July-December 2025, each pinned at its own hover throttle — but at
DIFFERENT hover throttles, because mass, battery and wind differed. Lay the logs side by side
and the 1x line sweeps across the set. A frame mode stands still while it does. That is
criterion (d)'s discriminator, assembled from flights that individually have none.

This is a Campbell diagram with the logs as its x-axis instead of time.

===========================================================================
PRE-REGISTRATION. WRITTEN AND COMMITTED BEFORE THE STATISTIC IS RUN ON ANY LOG.
===========================================================================

Same discipline as ThrustValidation, BuildValidation, resonance_analysis and impact_analysis:
the bound is fixed in advance so git shows it was chosen before the data. A bound moved to fit
the data it measures is not a bound. If the measurement busts it, that is reported and
diagnosed; it is NOT widened and REFERENCE_RESONANCE_HZ is NOT retuned to whatever came out.

THIS FILE AND ITS SELF-TEST ARE COMMITTED ALONE AND FIRST, with no corpus attached, which is
the precedent impact_analysis.py set after LTHL-18's process note: last time the instrument
and the data survey landed together (a9b3fa4) and the claim that the statistic predated the
data rested on the write-up rather than on git. The ordering here is verifiable instead.

---------------------------------------------------------------------------
0. WHAT I ALREADY KNOW, WHICH MAKES THIS A WEAKER PRE-REGISTRATION THAN THE OTHERS
---------------------------------------------------------------------------

STATED FIRST, BECAUSE A PRE-REGISTRATION THAT HIDES ITS CONTAMINATION IS WORSE THAN NONE.

resonance_analysis's bound was written blind. This one is not, and pretending otherwise would
be the exact failure the discipline exists to prevent. Before writing a line of this file I had
already measured, while building the INAV reader:

  * nine flights spanning motor command 1127-1363, an 18.6% spread;
  * their dominant spectral peak spanning 111-179 Hz, a factor of 1.61;
  * corr(motor command, peak) = 0.867 — i.e. I already know the dominant line TRACKS, which is
    the very thing section 3's ruler depends on;
  * that LOG00262's peak sits at 149.5 Hz, near REFERENCE_RESONANCE_HZ's neighbourhood;
  * that 58 of 141 files load and 46 have pre-filter gyroRaw.

What that contaminates, and what it does not:

  * CONTAMINATED: the belief that this method can work at all. The whole idea came from seeing
    that spread. Nothing can undo that, and it is why this file exists.
  * CONTAMINATED: section 4's discrimination thresholds are informed by knowing the 1x line
    moves by a factor of 1.61 across the set. They are therefore derived from a REQUIREMENT
    (how many standard errors must separate the two hypotheses) rather than picked, and the
    requirement is stated so it can be checked.
  * NOT CONTAMINATED: the agreement bound in section 1. Every term in it is a property of
    frames, arms, bolts and spectra, and not one of them was read off these logs. It is
    derived the same way the other two bounds were and it would be the same number if this
    corpus did not exist.
  * NOT CONTAMINATED: no candidate frequency has been extracted from any log by this method.
    The dominant peak I measured is the one this method must CALL A ROTOR ORDER, not the
    answer. If it comes back as a stationary mode, something is wrong with the method.

The honest summary: the BOUND is blind, the METHOD is not. That is a real reduction in the
strength of this pre-registration relative to LTHL-18's, and it is the reason section 6's
falsification requirements are stricter than either previous slice's.

---------------------------------------------------------------------------
1. THE AGREEMENT BOUND: 20%, DERIVED FROM ITS OWN TERMS
---------------------------------------------------------------------------

resonance_analysis.AGREEMENT_FRACTION is 0.25 for a within-log flight measurement;
impact_analysis.IMPACT_AGREEMENT_FRACTION is 0.20 for a bench tap. Neither is inherited. Term
by term, each as its effect on frequency:

  * Root fixity — arm bolt torque, plate stiffness, whether the arm is clamped between two
    plates or bolted to one.  TRANSFERS UNCHANGED, +-10%.  Still the largest term and still
    the least reducible: a real cantilever root is somewhere between clamped and pinned and
    moves with a hex key. Unchanged from both previous bounds.
  * Arm length definition.  +-3% in L, and f goes as L^-1.5, so +-4.5%.  This sits BETWEEN the
    flight bound's +-7.5% and the impact bound's +-3%, and the reason is who holds the
    calipers. The flight bound carried a catalogue figure whose convention the manufacturer
    does not state. The impact bound measures the frame in your own hand. Here the only
    admissible route is the aircraft's OWNER measuring their own frame to a written protocol
    and reporting a number — better than a catalogue, worse than your own hand, because
    transcription and convention risk survive a protocol that a caliper in your fingers does
    not.
  * The dropped arm-mass term.  TRANSFERS, 5%.  vibration_model.gd drops (33/140)*m_arm from
    the effective mass, a 7% correction on the reference build that varies down the catalog.
    It is a transport error BETWEEN frames and is carried because assuming this airframe is
    the reference build would be assuming the thing the measurement is for.
  * Unpublished tip mass.  DROPS TO ~0, as it did for the impact test, and for the same
    reason: the owner puts the motor, its hardware and the prop on a kitchen scale. Retained
    at +-1% for scale error, +-0.5% in f. If the owner will not weigh it, this term returns to
    -5% and the bound must be recomputed rather than stretched.
  * Peak picking.  +-1.5%.  Numerically the impact test's number, reached by a completely
    different route, and the difference matters. The impact test earns it by isolating one
    decaying sinusoid and reading its phase slope. This earns it by POOLING: a single hover
    spectrum's peak is worth about +-3%, bounded by the 6% half-power bandwidth at zeta=0.03,
    but the estimate is the median across tens of logs and the random half of that error goes
    as 1/sqrt(N). What does not shrink is the systematic half — spectral leakage, trend
    removal, the window — so this is floored at +-1.5% rather than driven to zero by adding
    logs. POOLING DOES NOT MAKE A BIASED ESTIMATOR UNBIASED.
  * NON-ROTATING.  DOES NOT APPLY. 0%.  The impact bound carries +-3% because a tap test has
    no gyroscopic stiffening and flight does. This IS flight. The term vanishes, which is the
    one place this method is strictly better than a tap test.

    sqrt(10^2 + 4.5^2 + 5^2 + 0.5^2 + 1.5^2) = 12.2%, call it 12% for one standard deviation.

The bound is set at 20%, which is 1.64 sigma — the same ~1.7 sigma convention both previous
bounds used, so the three numbers are comparable rather than differently generous.

IT LANDS ON THE IMPACT TEST'S NUMBER AND THAT IS A COINCIDENCE OF SIMILAR TERM LISTS, NOT AN
INHERITANCE. The arithmetic above was done before the comparison was noticed, and the term
lists differ in three places: arm length is worse here (+-4.5% vs +-3%), non-rotating vanishes
here (0% vs +-3%), and peak picking arrives by pooling rather than by isolation. They happen to
cancel. Written down because "we used 20% again" would otherwise look like copying.

The same caveat both previous bounds carry has not gone away: 160 Hz against 180 Hz is 11% and
would PASS. THIS MEASUREMENT CANNOT SETTLE THE 12% QUESTION kd_ceiling_for's comment raises.
It can catch an anchor wrong by more than a build's own spread.

CRITICALLY: this bound cannot be APPLIED to the INAV corpus, and that was true before it was
written. `Craft name` is empty in all 141 files, so criteria (b) and (c) — a named frame and
named motors/props — fail exactly as they have failed every log LTHL-18 has ever examined.
The bound is fixed now so that it is already fixed if the owner ever measures their aircraft.
Until then this file can produce a FREQUENCY and a STATIONARITY VERDICT and no agreement test
at all, and it must say so rather than quietly comparing against the reference build.
"""

CAMPBELL_AGREEMENT_FRACTION = 0.20

"""
---------------------------------------------------------------------------
2. THE CORPUS THIS IS ALLOWED TO RUN ON. All required.
---------------------------------------------------------------------------

  a. UNFILTERED GYRO, per log, by the same measured standard everything else in this project
     uses — _looks_prefilter, never a header or a field name. Unchanged from LTHL-18.
  b. A NAMED, MEASURED FRAME and c. NAMED MOTORS AND PROPS, for the agreement test only. A
     corpus without them still produces a frequency and a verdict; it produces no PASS or FAIL.
     This is stated as a separate gate rather than a blanket refusal because the stationarity
     result is worth having on its own and the frequency is worth recording for later.
  d. REPLACED. This is the whole point of the file. "A slow throttle sweep" becomes "a corpus
     whose empirical 1x line spans enough range to resolve the two hypotheses", which is
     section 4's SE gate and is measured, not asserted.
  e. LOGGED RPM. STILL REQUIRED, AND STILL NOT SATISFIED — but its role changes. Order
     tracking needed rpm to know where each harmonic was inside one frame. Here the corpus
     supplies its own ruler (section 3), so rpm is not needed to BUILD the x-axis. It is
     needed to LABEL it: without rpm the orders cannot be named, only counted. See section 3
     for what that costs and why it is survivable.

  f. NEW, AND IT IS THE ONE THIS METHOD ADDS: ONE AIRCRAFT, MECHANICALLY UNCHANGED.
     Every previous criterion was about one log. This one is about the corpus, and it is the
     assumption the whole method rests on: if the airframe changed between July and December,
     a "stationary" line has no reason to be stationary and a moving one has no reason to be
     an order.

     `Firmware type`, `looptime`, the PID table and the filter config being identical across
     141 files is a FIRMWARE claim and is not the claim that matters. Bolts loosen. Props get
     replaced after a crash. An arm gets swapped and nothing in the log says so.

     This cannot be verified from the logs, which is why it is a stated ASSUMPTION and why
     section 5's drift gate exists to catch its violation rather than to prove its truth.

---------------------------------------------------------------------------
3. THE RULER: an empirical 1x, and what having no rpm actually costs
---------------------------------------------------------------------------

LTHL-50 flagged this as the thing to settle first, and it is. The corpus has no rpm
(`motor_pwm_protocol:0`, PWM at 400 Hz, no telemetry — 9be5b5a), so the x-axis cannot be a
rotation frequency derived from throttle. Deriving one needs a thrust constant this project
has repeatedly refused to invent, and order tracking on an invented frequency measures the
invention.

THE RESOLUTION: do not derive the x-axis. MEASURE it.

In each log k, ONE_X_k is the frequency of the spectral peak whose across-corpus frequency is
most strongly rank-correlated with that log's mean motor command. That is a measured quantity
with no constant in it. The corpus supplies its own ruler.

Two things this costs, both stated rather than hidden:

  * THE ORDERS CANNOT BE NAMED. Without rpm there is nothing to say whether the tracking line
    chosen as ONE_X is the motor fundamental, blade passage, or the second harmonic. The
    method therefore never claims an order NUMBER. It says "rotor-locked" or "stationary",
    and rotor-locked is enough to reject a candidate. A misidentified ONE_X rescales every
    order label and changes NO verdict, because every rotor order — 1x, 3x, whatever — has
    the same log-log slope of 1 against any other rotor order. THE STATISTIC IS INVARIANT TO
    WHICH ROTOR LINE IS PICKED AS THE RULER. That is the property that makes this survivable
    without rpm, and it is worth stating plainly because it is not obvious.
  * IT ASSUMES ONE OF THE PEAKS IS A ROTOR LINE. If every visible line were structural the
    ruler would be a mode and everything would come back "stationary" together. Section 5's
    monotonicity gate is what refuses that case: a structural line has no reason to be
    monotone in throttle, and ONE_X is required to be.

CIRCULARITY, AND WHY THIS IS NOT IT. Picking the ruler by correlation with motor command, and
then testing candidates against the ruler, looks circular and is not: the ruler is chosen by
correlation with an EXTERNAL variable (the throttle command, which is in the log and is not a
spectral quantity), and candidates are then judged against the ruler by a DIFFERENT statistic
(log-log slope). A candidate cannot be pulled into the ruler's group by having been used to
build it. The ruler peak is nonetheless excluded from candidacy, because a line cannot be
evidence about itself.

---------------------------------------------------------------------------
4. THE STATISTIC: one slope, two hypotheses, symmetric treatment
---------------------------------------------------------------------------

For a candidate line at frequency f, fitted across the logs in which it appears:

    b  =  d(ln f) / d(ln ONE_X)

  * A ROTOR ORDER of any order q has f = q * ONE_X, so ln f = ln q + ln ONE_X and b = 1
    EXACTLY, for every q. No exceptions and no free parameters.
  * A STRUCTURAL MODE has f independent of rotation, so b = 0.

Nothing else about the two hypotheses differs in how they are handled, and that symmetry is
deliberate. The obvious wrong way to build this is to group peaks across logs by absolute
frequency proximity, which would find stationary lines by construction and would scatter
rotor lines into fragments that never form a group. THIS ANALYSIS MUST NOT DO THAT. Both
hypotheses get the SAME matching window, the same recurrence requirement and the same scoring,
and the verdict comes from b.

THE THRESHOLD, and it is derived from a requirement rather than picked:

The two hypotheses sit at b = 0 and b = 1, one full unit apart. The standard error of a
log-log slope is

    SE(b)  ~=  sigma_ln_f  /  ( sqrt(N) * sigma_ln_1x )

with sigma_ln_f the per-log peak-reading error (+-3%, i.e. 0.03 in log terms, from section 1's
peak-picking term before pooling), N the number of logs the candidate appears in, and
sigma_ln_1x the spread of the ruler across those logs.

REQUIREMENT: the two hypotheses must be at least 10 standard errors apart before this method
is allowed to distinguish them at all. 10 SE over a separation of 1.0 gives SE <= 0.1; the
gate below is set at 0.03, i.e. THIRTY standard errors, because the cost of demanding a better
corpus is waiting and the cost of a false stationary line is a wrong anchor in a tune.

B_STATIONARY is then 0.15: five times the gated SE, and far below the 1.0 a rotor order must
show. A candidate is stationary if |b| <= 0.15 and rotor-locked if |b - 1| <= 0.15. Anything
between is NEITHER and is reported as such rather than forced into one bucket — an
intermodulation product or an aliased line can sit anywhere, and a method that always returns
a verdict is not measuring.

THIS GATE MAY REFUSE THE CORPUS THAT INSPIRED THE METHOD, and the arithmetic is written here
so that outcome is a prediction and not an excuse. sigma_ln_f = 0.03 and a ruler spanning a
factor of 1.61 spread roughly uniformly gives sigma_ln_1x ~= 0.48/sqrt(12) ~= 0.139, so
SE(b) <= 0.03 needs sqrt(N) >= 0.03/(0.03*0.139), i.e. N >= 52 LOGS IN WHICH THE SAME
CANDIDATE APPEARS. 46 of the 141 files have pre-filter gyroRaw. If the candidate appears in
all of them that is 46, and the gate REFUSES at SE = 0.032.

That is the pre-registered prediction: this corpus is marginal and probably just misses. It is
written down before running because "we got 46 and the gate wanted 52" is a result, and
lowering the gate afterwards to 0.033 would be the exact move this file exists to prevent.
"""

MATCH_WINDOW = 0.10
DRIFT_LIMIT = 0.06
B_STATIONARY = 0.15
MAX_SLOPE_SE = 0.03
PEAK_READ_SIGMA = 0.03
MIN_LOGS = 12
MIN_LOG_FRACTION = 0.6
ONE_X_MONOTONICITY = 0.7
AXIS_AGREEMENT = 0.06

"""
---------------------------------------------------------------------------
5. CALLING A STATIONARY LINE A FRAME MODE: four parts, all required
---------------------------------------------------------------------------

LTHL-49 needed a three-part rule because a room resonance and an arm mode both make a clean
peak. The same problem is worse here, because EVERYTHING on this aircraft that is not a rotor
is stationary: the FC soft-mount, the GPS mast, a camera bracket, a loose battery strap. b = 0
says "not a rotor order". It does not say "arm bending mode".

  (a) STATIONARY.  |b| <= B_STATIONARY, with SE(b) <= MAX_SLOPE_SE. Section 4.

  (b) RECURRENT.  Present in at least MIN_LOG_FRACTION of admissible logs, and in at least
      MIN_LOGS of them absolutely. A line in three flights out of forty is an event, not a
      property of the airframe. 0.6 is LTHL-49's MIN_STRIKE_FRACTION, reused deliberately:
      the question is the same question — did this recur, or did it happen.

  (c) ON BOTH ROLL AND PITCH, within AXIS_AGREEMENT.  This is the weakest of the four and is
      labelled as such. An X-quad's arm bending modes couple into roll and pitch nearly
      symmetrically, because the four arms are at 45 degrees to both axes. A single-cantilever
      appendage — a GPS mast, an antenna, a camera arm — bends in a preferred plane and shows
      up strongly on one axis. So a candidate on one axis only is rejected.

      IT IS WEAKER THAN LTHL-49's PROPS-OFF TEST AND THAT MUST NOT BE FORGOTTEN. The props-off
      test moved a physical mass and predicted the frequency shift; this only observes a
      symmetry. A symmetric appendage on the centre stack — the FC itself on its grommets —
      passes this test. It narrows the field. It does not identify.

  (d) NOT DRIFTING.  The spread of the matched frequencies, as an interquartile range over
      the median, must be <= DRIFT_LIMIT. This is the only handle on criterion 2f, the
      one-aircraft assumption, that the logs themselves provide: if the airframe changed
      mid-corpus the "stationary" line moved, and it moved for a reason that is not rotation
      and will not show up in b.

      DRIFT_LIMIT is 0.06 and MATCH_WINDOW is 0.10, so this is a real constraint INSIDE the
      window rather than a restatement of it. A line drifting more than 6% but less than 10%
      is matched, measured and then REFUSED, with the drift reported — which is the outcome
      that tells the owner their aircraft changed. Beyond 10% it falls out of the window and
      fails (b) recurrence instead, and the diagnostic must say "did not recur" rather than
      "no mode found", because those mean different things to whoever reads it.

Where the previous rules had a physical intervention available and this one does not, the
result is a CANDIDATE, and the word used in the output is "candidate". Confirming it needs the
frame in someone's hands and a tap test — which is LTHL-49, already built, and the honest
recommendation this file should make when it finds something.

---------------------------------------------------------------------------
6. PROVING THE STATISTIC CAN FAIL. Stricter here than in either previous slice.
---------------------------------------------------------------------------

Section 0 admits the method was inspired by the data. That makes every "it works" result
suspect and puts the whole weight on the controls. The self-test must show all of:

  1. a planted STATIONARY mode is recovered, and its frequency is right;
  2. a planted ROTOR line at any order is called rotor-locked and NEVER stationary — including
     when it happens to sit near the planted mode in the middle of the corpus, which is the
     configuration that makes the two look alike in a single log;
  3. MOVING THE PLANTED MODE MOVES THE ANSWER. LTHL-18's synthetic sweep was a closed loop
     that could not have disagreed, and only the moved-anchor test caught it. Same guard.
  4. a corpus with NO stationary line returns nothing — not a best candidate, nothing;
  5. a corpus whose ruler does not span enough range is REFUSED BY THE SE GATE rather than
     analysed, and the refusal reports the SE it measured;
  6. a stationary line on ONE AXIS ONLY is rejected by rule (c);
  7. a line that DRIFTS across the corpus is refused by rule (d) with the drift reported;
  8. and the one that matters most given section 0: THE DOMINANT TRACKING LINE MUST COME BACK
     ROTOR-LOCKED. If a corpus built to look like the INAV set returns its own ruler-adjacent
     dominant peak as a stationary mode, the method is finding what it went looking for.

---------------------------------------------------------------------------
7. WHAT THIS FILE DOES NOT DO
---------------------------------------------------------------------------

It does not extract peaks from a log and it does not identify ONE_X from a spectrum. It takes
per-log peak lists and a per-log mean motor command, and it does the cross-log part: ruler
selection, hypothesis fitting, the four-part rule and the gates. Spectral extraction is the
next slice and it depends on the reader, not on this.

It does not run on the corpus. That is deliberate and it is the point of committing this
alone: the survey comes second, in its own commit, so the ordering is a fact about git rather
than a claim in a write-up.

It touches no bound. AGREEMENT_FRACTION, IMPACT_AGREEMENT_FRACTION, DAMPING_AGREEMENT_FACTOR
and REFERENCE_RESONANCE_HZ are all untouched by this file.
"""
import math
import os
import sys
from dataclasses import dataclass, field

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    sys.exit("numpy is required: python3 -m venv .venv && .venv/bin/pip install numpy")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

VERDICT_STATIONARY = "stationary"
VERDICT_ROTOR = "rotor-locked"
VERDICT_NEITHER = "neither"


@dataclass
class LogPoint:
    """One log's contribution to the corpus. Peaks in Hz, per axis.

    Deliberately NOT a Trace and deliberately carrying no build: this is the cross-log half of
    the analysis and a corpus is not an aircraft description. See section 1's closing note.
    """

    name: str
    motor_command: float
    #: {"roll": [hz, ...], "pitch": [hz, ...]} — every peak found, not just the tall ones.
    #: Filtering to "interesting" peaks before this point would decide the answer upstream.
    peaks: dict


@dataclass
class Ruler:
    """The empirical 1x. Section 3."""

    hz: "np.ndarray"           #: ONE_X per log, in corpus order
    motor: "np.ndarray"
    spearman: float
    evidence: str


@dataclass
class Candidate:
    """One line tracked across the corpus."""

    hz: float                  #: median of the matched frequencies
    verdict: str
    b: float
    b_se: float
    logs: int
    of_logs: int
    drift: float
    axes: tuple
    rejections: list = field(default_factory=list)

    @property
    def frame_mode_candidate(self) -> bool:
        return not self.rejections and self.verdict == VERDICT_STATIONARY


def _spearman(a, b) -> float:
    """Rank correlation, without scipy. Used for a monotonicity gate, not for a measurement."""
    a, b = np.asarray(a, dtype=float), np.asarray(b, dtype=float)
    if len(a) < 3 or a.std() <= 0 or b.std() <= 0:
        return 0.0
    ra = np.argsort(np.argsort(a)).astype(float)
    rb = np.argsort(np.argsort(b)).astype(float)
    if ra.std() <= 0 or rb.std() <= 0:
        return 0.0
    return float(np.corrcoef(ra, rb)[0, 1])


def choose_ruler(points, axis="roll") -> Ruler:
    """Pick ONE_X per log: the tracked line, measured, never derived from throttle. Section 3.

    The candidate rulers are the peaks themselves. For each log we need ONE frequency, and the
    line we want is the one that moves WITH the throttle across the corpus. So: for each
    ordinal position in the frequency-sorted peak list, take that peak from every log and
    score it by rank correlation with motor command. The best-scoring position is the ruler.

    Ordinal position is used rather than absolute frequency on purpose, and it is the same
    trap section 4 warns about from the other side: grouping by absolute frequency would
    fragment exactly the moving line we are trying to find.
    """
    motor = np.array([p.motor_command for p in points], dtype=float)
    depth = min(len(p.peaks.get(axis, [])) for p in points) if points else 0
    if depth == 0:
        raise ValueError("choose_ruler: at least one log has no peaks on this axis")
    best, best_rho = None, -2.0
    for ordinal in range(depth):
        hz = np.array([sorted(p.peaks[axis])[ordinal] for p in points], dtype=float)
        rho = _spearman(motor, hz)
        if rho > best_rho:
            best, best_rho = hz, rho
    if best_rho < ONE_X_MONOTONICITY:
        raise ValueError(
            f"no ruler: the best-tracking line has Spearman {best_rho:.3f} against motor "
            f"command, below {ONE_X_MONOTONICITY}. Nothing in this corpus moves monotonically "
            "with throttle, so there is no rotor line to measure the others against — and a "
            "corpus where every line is stationary cannot tell a mode from a ruler."
        )
    return Ruler(hz=best, motor=motor, spearman=best_rho,
                 evidence=(f"empirical 1x from the peak tracking motor command at Spearman "
                           f"{best_rho:.3f}, spanning {best.min():.1f}-{best.max():.1f} Hz "
                           f"(x{best.max() / best.min():.2f}); orders are NOT named"))


def _fit_slope(ln_x, ln_y):
    """b and its standard error, from the residuals. Section 4."""
    n = len(ln_x)
    if n < 3:
        return float("nan"), float("inf")
    x = ln_x - ln_x.mean()
    sxx = float((x ** 2).sum())
    if sxx <= 0:
        return float("nan"), float("inf")
    b = float((x * (ln_y - ln_y.mean())).sum() / sxx)
    # The SE uses the PRE-REGISTERED per-log reading error, not the fit's own residual scatter.
    # Using the residuals would let a candidate that happens to fit tightly claim a precision
    # the measurement does not have, and would make the gate easier exactly when the data is
    # most flattering. See section 4.
    return b, float(PEAK_READ_SIGMA / math.sqrt(sxx))


def track(points, ruler: Ruler, axis="roll", candidates=None):
    """Fit b for every candidate line in the corpus. Symmetric between the two hypotheses."""
    ln_1x = np.log(ruler.hz)
    if candidates is None:
        # Every peak in every log is a candidate seed, deduplicated by the match window so the
        # same line is not tracked twice. The ruler's own peaks are excluded: a line cannot be
        # evidence about itself (section 3).
        seeds = sorted({round(hz, 3) for p in points for hz in p.peaks.get(axis, [])})
        candidates, taken = [], []
        for hz in seeds:
            if any(abs(hz - t) <= MATCH_WINDOW * t for t in taken):
                continue
            if any(abs(hz - r) <= 1e-9 for r in ruler.hz):
                continue
            candidates.append(hz)
            taken.append(hz)

    out = []
    for seed in candidates:
        idx, matched = [], []
        for i, p in enumerate(points):
            near = [hz for hz in p.peaks.get(axis, []) if abs(hz - seed) <= MATCH_WINDOW * seed]
            if near:
                idx.append(i)
                matched.append(min(near, key=lambda h: abs(h - seed)))
        if len(idx) < 3:
            continue
        matched = np.array(matched, dtype=float)
        b, se = _fit_slope(ln_1x[idx], np.log(matched))
        q75, q25 = np.percentile(matched, [75, 25])
        median = float(np.median(matched))
        out.append(Candidate(
            hz=median,
            verdict=(VERDICT_STATIONARY if abs(b) <= B_STATIONARY
                     else VERDICT_ROTOR if abs(b - 1.0) <= B_STATIONARY
                     else VERDICT_NEITHER),
            b=b, b_se=se, logs=len(idx), of_logs=len(points),
            drift=float((q75 - q25) / median) if median > 0 else float("inf"),
            axes=(axis,),
        ))
    return out


def identify_frame_mode(points, per_axis=("roll", "pitch")):
    """The four-part rule of section 5. Returns (candidates, ruler, notes).

    Every candidate comes back, with its rejections attached, because a rule that silently
    drops what it rejected cannot be audited — the same reason LTHL-49's Identification carries
    its `rejected` list.
    """
    notes = []
    ruler = choose_ruler(points, axis=per_axis[0])
    notes.append(ruler.evidence)

    by_axis = {ax: track(points, ruler, axis=ax) for ax in per_axis}
    primary = by_axis[per_axis[0]]

    for cand in primary:
        # (a) stationary, and resolvable at all
        if cand.b_se > MAX_SLOPE_SE:
            cand.rejections.append(
                f"SE(b) = {cand.b_se:.4f} > {MAX_SLOPE_SE}: this corpus cannot separate b=0 "
                f"from b=1 for a line appearing in {cand.logs} logs. Needs more logs or a "
                "wider spread of hover throttles, NOT a wider gate")
        if cand.verdict != VERDICT_STATIONARY:
            cand.rejections.append(f"b = {cand.b:+.3f} ({cand.verdict})")
        # (b) recurrent
        if cand.logs < MIN_LOGS or cand.logs < MIN_LOG_FRACTION * cand.of_logs:
            cand.rejections.append(
                f"did not recur: {cand.logs}/{cand.of_logs} logs, need "
                f"{max(MIN_LOGS, math.ceil(MIN_LOG_FRACTION * cand.of_logs))}")
        # (c) both axes
        others = [c for ax in per_axis[1:] for c in by_axis[ax]
                  if abs(c.hz - cand.hz) <= AXIS_AGREEMENT * cand.hz]
        if not others:
            cand.rejections.append(
                f"on {per_axis[0]} only: no matching line within {AXIS_AGREEMENT:.0%} on "
                + "/".join(per_axis[1:]) + " — a single-plane appendage, not an arm mode")
        else:
            cand.axes = tuple(per_axis)
        # (d) not drifting
        if cand.drift > DRIFT_LIMIT:
            cand.rejections.append(
                f"drifted {cand.drift:.1%} across the corpus (limit {DRIFT_LIMIT:.0%}): the "
                "airframe did not stay one airframe, so criterion 2f is violated")

    if not any(c.frame_mode_candidate for c in primary):
        notes.append("NO FRAME MODE CANDIDATE. Every line was rejected; reasons are attached "
                     "to each candidate and are not the same as 'nothing was found'.")
    return primary, ruler, notes


def report(cands, ruler, notes, modelled_hz=None, build_measured=False):
    """Print the verdict. Refuses to quote an agreement unless the build was MEASURED."""
    for n in notes:
        print(f"  {n}")
    for c in sorted(cands, key=lambda c: -c.logs):
        mark = "CANDIDATE" if c.frame_mode_candidate else "rejected "
        print(f"  {mark} {c.hz:7.1f} Hz  b = {c.b:+.3f} +- {c.b_se:.4f}  "
              f"{c.logs}/{c.of_logs} logs  drift {c.drift:.1%}  axes {'+'.join(c.axes)}")
        for r in c.rejections:
            print(f"              - {r}")

    hits = [c for c in cands if c.frame_mode_candidate]
    if not hits:
        return None
    best = max(hits, key=lambda c: c.logs)
    if not build_measured or modelled_hz is None:
        # Section 1's closing note, enforced rather than remembered.
        print("\n  NO AGREEMENT TEST. Criteria (b) and (c) are unmet: this corpus has no\n"
              "  measured frame or tip mass, so there is nothing to compare the frequency to.\n"
              f"  Recorded for later: {best.hz:.1f} Hz, a stationary CANDIDATE, not a\n"
              "  confirmed frame mode. Confirming it needs the frame in hand and a tap test\n"
              "  (LTHL-49), which measures the same quantity with a physical intervention.")
        return best
    error = (best.hz - modelled_hz) / modelled_hz
    inside = abs(error) <= CAMPBELL_AGREEMENT_FRACTION
    print(f"\n  measured {best.hz:.1f} Hz vs modelled {modelled_hz:.1f} Hz -> {error:+.1%} "
          f"({'INSIDE' if inside else 'OUTSIDE'} the pre-registered "
          f"{CAMPBELL_AGREEMENT_FRACTION:.0%})")
    return best
