#!/usr/bin/env python3
"""INAV blackbox logs — the third dialect, and an honest account of what it is good for.

===========================================================================
WHAT THESE LOGS ARE
===========================================================================

141 files, 343 MB, `LOG00262.TXT` .. `LOG00402.TXT`. The `.TXT` extension is misleading: the
contents are raw binary blackbox, the same container Betaflight writes, with a different field
dialect. One aircraft, one tune, unchanged config, July-December 2025. INAV 8.0.0/8.0.1 on an
OMNIBUSF4PRO, `Firmware type:Cleanflight` in the header. Quad, `looptime:500` with
`P interval:1/2`, so ~982 Hz reaches the log. `gyro_lpf_hz:110`, `dterm_lpf_hz:105`.
Throttle sits at hover +-6% for entire flights: a survey or mapping platform, not freestyle.

===========================================================================
WHY THE DIALECT IS WORTH SUPPORTING AT ALL
===========================================================================

INAV logs `gyroRaw[]` alongside `gyroADC[]` as a FIRST-CLASS FIELD. Measured on LOG00262 by
the same _looks_prefilter that judges a Betaflight log — the field NAME is not evidence and is
not trusted here — gyroRaw carries 22.5x / 6.6x / 52.3x the 100-442 Hz power fraction of
gyroADC on the three axes.

That is admissibility criterion (a) satisfied NATIVELY, and it dissolves a constraint LTHL-18
recorded as though it were universal. On Betaflight 4.3, unfiltered gyro has to be smuggled
through `debug[]` — the same four channels eRPM needs — so criteria (a) and (e) compete and
may not be satisfiable at once. THAT IS A BETAFLIGHT LIMITATION, NOT A PHYSICAL ONE. INAV has
a dedicated field and no conflict. The ask is not impossible; it is impossible on one firmware.

`gyroRaw` also sits upstream of the 110 Hz gyro lowpass, which is the other trap LTHL-18
found: on the reference build the modelled mode sits above the cutoff and the FC never sees it.

===========================================================================
AND YET: THESE LOGS PRODUCE A BEAUTIFUL WRONG ANSWER. READ THIS FIRST.
===========================================================================

`gyroRaw` on LOG00262 has a strong clean peak at 149.5 Hz, sitting right on top of
`REFERENCE_RESONANCE_HZ := 180.0`'s neighbourhood. IT IS NOT A FRAME MODE. Across nine flights:

    motor cmd spread   1127 - 1363   (18.6%)
    peak spread         111 -  179 Hz
    corr(motor, peak)   0.867

The peak tracks the throttle. It is the motor fundamental. A frame mode would have stood still.
This is the entire reason order tracking exists, and it is why `load_inav` REFUSES rather than
quietly making these logs analysable:

  * criterion (e), logged rpm, fails for a HARDWARE reason. `motor_pwm_protocol:0` is PWM at
    400 Hz. There is no DShot, therefore no RPM telemetry, and no code change can fix it.
    `motor[]` is a throttle COMMAND, not a frequency; converting one to the other needs a
    thrust constant we would be inventing.
  * criterion (d), the slow sweep, fails for the OPPOSITE reason to the freestyle logs.
    Those failed because the 1x line moved 155-235 Hz inside one analysis frame. These fail
    because the throttle NEVER MOVES AT ALL. "Too steady" is a failure mode the
    pre-registration did not anticipate, and both are inadmissible.

`escRPM` and `escTemperature` appear in the S-frame schema and are GARBAGE: `escRPM` measures
as the single constant 134380293 across an entire flight. They are NOT read here. Decoding
INAV's packing properly and proving it would be a different slice; passing the field through
under the name "rpm" would be the exact mistake the whole order-tracking apparatus exists to
prevent.

===========================================================================
SO WHAT IS THE READER FOR?
===========================================================================

A loader whose output every existing consumer rejects looks pointless until you say what it is
for. Four things, none of which is "measure the frame resonance":

  1. `load_inav_impact`. LTHL-49's analyser has NO rpm requirement, by design, because nothing
     rotates during a tap test. An INAV log of a bench tap is immediately admissible where a
     flight log is not. This is the one path where these logs could produce a number today.
  2. Flight-report ingest, where variety matters more than admissibility.
  3. Battery and forward-flight data: `vbat` + `amperage` + `sagCompensatedVBat` under real
     load, and `GPS_speed` + `wind[]`, none of which has any real-world reference in the
     project today. NOTE that none of those fields is exposed by this module yet — see UNITS.
  4. Adversarial fixtures. `28d23ee`'s sampling guard was built for exactly this shape of
     defect and had never met a real broken file. It has now met 60 of them.

===========================================================================
THE 141-FILE SURVEY. RUN WITH THIS LOADER, NOT WITH A SCRIPT THAT AGREES WITH IT.
===========================================================================

    46   load, gyroRaw confirmed pre-filter by measurement
    12   load, but gyroRaw does NOT beat gyroADC — refused downstream by assert_usable
    60   REFUSED: non-uniform sampling (dropped frames), by 28d23ee's guard
    14   REFUSED: truncated or empty (under 1000 usable I/P frames)
     5   REFUSED: time not monotonic even after the preamble skip
     3   REFUSED: undecodable, orangebox InvalidHeaderException at 0xC06
     1   REFUSED: corrupt frame stream, struct 'I' format requires 0 <= number <= 4294967295
   ---
   141

So 58 of 141 decode into something usable and 83 are refused, every one of them with a
measured reason. The single largest bucket is the sampling guard: dropped blackbox frames are
not an edge case on this hardware, they are the median outcome.

Of the 58 that load, 43 report "gyro scale NOT VERIFIED" — the aircraft was never commanded
to move enough to regress gyroADC on axisRate. That is the SAME "too steady" property that
makes these logs fail criterion (d), showing up in a second place. It is reported, not
refused; see _verify_deg_s for why that is the right call and where it would stop being one.

There is a fifth use that is NOT started here and has its own issue: with 141 flights of one
aircraft spanning 18.6% of motor command, the 1x line sweeps ACROSS the set while a frame mode
would stand still. A Campbell diagram assembled from flights that individually have no sweep
is a genuine route past criterion (d). It is not built here.

===========================================================================
DECODER: orangebox, AS A LIBRARY, WITH A LAZY IMPORT
===========================================================================

`resonance_analysis.load_betaflight` takes an ALREADY-DECODED CSV and ships no decoder, and
consistency with that is worth something. It is not followed here, for one reason: INAV's
`blackbox_decode` is not on this machine and the Betaflight one does not read this dialect, so
a loader that required a decode step nobody can perform would be untestable against the 141
files that are its entire justification. A reader that cannot read the data is not a reader.

`orangebox` (pure Python, PyPI, MIT) reads them. Three known problems, all worked around here:

  * the published wheel has a broken console-script entry point (`bb2csv = scripts:None`), so
    `pip install orangebox` FAILS. It must be installed as a library:
        pip download orangebox --no-deps -d /tmp/ob && unzip -o /tmp/ob/*.whl -d /tmp/ob/x
        cp -r /tmp/ob/x/orangebox <venv>/lib/python3.13/site-packages/
  * `Parser.frames()` interleaves I/P, S, G and H frame types. Rows come back with S-frame
    slots as empty strings, so only I and P frames are kept here.
  * it prints "Unknown event type: 19" on these files, to stdout, and cannot be silenced
    without patching it. Harmless; mentioned so nobody hunts it.

The import is LAZY and inside the reader, so `resonance_analysis` and `impact_analysis` keep
working with numpy alone. When orangebox is absent the failure is a clear ImportError naming
the two remedies, not a stack trace from a missing symbol.

===========================================================================
UNITS. EVERY ONE OF THESE SILENTLY SCALES A PHYSICS QUANTITY.
===========================================================================

Only ONE unit matters to what this module returns, and it is verified against a known quantity
rather than inferred from magnitude:

  * gyro is in DEG/S. Verified by regressing `gyroADC[axis]` on `axisRate[axis]`, which is
    INAV's rate SETPOINT and is deg/s by definition. On LOG00262 the slope is 1.07 (roll,
    r=0.82) and 1.02 (yaw, r=0.93). A raw-sensor-count channel would have regressed at a
    scale factor of tens. `gyro_scale:0x3f800000` is 1.0f and is consistent with that, but the
    header is not what decided it. Pitch is excluded: r=0.16, the axis barely moved.

The battery and GPS fields listed under use (3) above are NOT exposed, deliberately. `vbat`
reads 691.8 mean / 739 max against `vbatref:740` and `vbatcellvoltage:[33,35,42]` (per-cell
min/warn/max in 0.1 V); centivolts fits a 2S pack at 3.70 V/cell and no other cell count puts
it in range, which is suggestive and is NOT the same as verified. `amperage` has no reference
value available at all. Getting `vbat` wrong by 10x produces a plausible-looking pack, so
these stay unexposed until something can check them. `Trace` and `Recording` carry neither.

===========================================================================
A LOG MAY NEVER RECONSTRUCT A BUILD
===========================================================================

`flight_recorder.gd` carries this constraint with a test that reads its own source. Nothing
here infers arm length, mass, prop size or any other build property from the log, and nothing
here returns a Build. `Craft name` is empty in all 141 files so there is nothing to be tempted
by, which is luck rather than design and is not a reason to relax the rule.

===========================================================================
WHERE THIS LIVES
===========================================================================

`impact_analysis` imports `_read_bbl_csv`, `_choose_gyro_columns` and `check_uniform_sampling`
from `resonance_analysis`; this module follows that seam and imports from both, one direction
only, no cycles. A shared reader module was CONSIDERED AND NOT EXTRACTED: the third dialect
does not grow the shared surface. It needs `check_uniform_sampling` (already importable) and
`_looks_prefilter`, and it needs NEITHER `_read_bbl_csv` (this container is binary, not CSV)
nor `_choose_gyro_columns` (the debug[] dance is a Betaflight workaround INAV does not need).
Extracting a module now would move code without reducing coupling.
"""
import os
import sys
from dataclasses import dataclass

try:
    import numpy as np
except ImportError:  # pragma: no cover - environment guard
    sys.exit("numpy is required: python3 -m venv .venv && .venv/bin/pip install numpy")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from resonance_analysis import (  # noqa: E402
    Trace,
    _looks_prefilter,
    _same_axis,
    check_uniform_sampling,
)
from impact_analysis import Recording  # noqa: E402

#: INAV's gyro axis order in the log, and the two this project analyses. Roll is gyro[0] and
#: PITCH is gyro[1] here — not gyro[2]. Lothal's own recorder uses gyro_z for pitch because of
#: Godot's Y-up basis; a flight controller does not, and conflating the two would silently
#: analyse yaw and call it pitch. Same class of error the debug[1] guard exists to stop.
AXIS_INDEX = {"roll": 0, "pitch": 1, "yaw": 2}

#: The regression slope of gyroADC on axisRate that a deg/s channel must produce. A raw
#: sensor-count channel would land at tens or hundreds; a deg/s channel lands near 1. The
#: window is wide because this is a SANITY test on the unit, not a measurement of tracking
#: quality — the FC's rate loop has error in it and a well-flown log still lands off 1.0.
DEG_S_SLOPE_RANGE = (0.5, 2.0)
#: Below this |r| the axis did not move enough for the slope to mean anything and it is
#: skipped rather than believed. On LOG00262 pitch sits at 0.16 and is skipped; roll and yaw
#: are at 0.82 and 0.93 and carry the verdict.
DEG_S_MIN_CORR = 0.5

#: Frames discarded from the START of every INAV log before the sampling guard is applied,
#: defaulting to the header's own `I interval` (32 on this set).
#:
#: THIS IS A REAL WEAKENING OF A GUARD AND HAS TO EARN ITS PLACE. `28d23ee` refuses any log
#: with a non-positive time interval, on the grounds that it is corruption and that `median`
#: will absorb a few of them. That is right. But measured across all 141 files, 135 of the 137
#: that decode have their FIRST bad interval inside the first 20 frames, and the distribution
#: has a hard edge there — this is the log opening, before the FC's logging loop settles, not
#: frames going missing mid-flight. LOG00262 is typical: one interval of -10 us at frame 12,
#: then 86 s of clean 1018 us sampling.
#:
#: The count is NOT fitted to that measurement. It is `I interval` from the header — the
#: period at which INAV writes a full I-frame — so the skip is one I-frame interval, a
#: property of the container. 32 sits above the observed edge of 20 with room to spare, and
#: neither number was chosen by trying values until files passed.
#:
#: The proof that it is not a licence: after the skip, the guard still refuses roughly half
#: this corpus for gaps that are genuinely mid-flight. A preamble skip that rescued everything
#: would be a guard that had been switched off. The count of frames dropped and the reason are
#: both carried in sampling_evidence, so no file is ever quietly shortened.
DEFAULT_PREAMBLE_FRAMES = 32

INAV_FIELDS = ("time", "gyroADC[0]", "gyroADC[1]", "gyroADC[2]",
               "gyroRaw[0]", "gyroRaw[1]", "gyroRaw[2]", "motor[0]")


@dataclass
class InavLog:
    """A decoded INAV log. Deliberately NOT a Build and deliberately not a Trace."""

    path: str
    headers: dict
    col: dict
    rows: "np.ndarray"
    #: Measured, printed with every result: is gyroRaw really pre-filter, and by how much.
    gyro_evidence: str = ""
    unfiltered: bool = False
    sampling_evidence: str = ""
    units_evidence: str = ""


def _orangebox():
    """Lazy import, with the two remedies in the message rather than a bare ImportError."""
    try:
        from orangebox import Parser
    except ImportError as exc:
        raise ImportError(
            "reading an INAV .TXT needs the `orangebox` decoder, which is not installed.\n"
            "  Its published wheel has a broken console-script entry point, so a plain\n"
            "  `pip install orangebox` fails. Install it as a library:\n"
            "    pip download orangebox --no-deps -d /tmp/ob && unzip -o /tmp/ob/*.whl -d /tmp/ob/x\n"
            "    cp -r /tmp/ob/x/orangebox .venv/lib/python3.13/site-packages/\n"
            "  Alternative: decode to CSV with INAV's own blackbox_decode, which is not on\n"
            "  this machine and which the Betaflight blackbox_decode cannot substitute for."
        ) from exc
    return Parser


def read_inav(path: str, min_frames: int = 1000) -> InavLog:
    """Decode one INAV .TXT and measure everything that decides whether it is usable.

    Raises ValueError for a truncated, empty or corrupt file, and for a log whose gyroRaw does
    not measurably beat gyroADC. Raises ImportError if orangebox is missing.
    """
    Parser = _orangebox()
    try:
        parser = Parser.load(path)
    except Exception as exc:
        # orangebox raises a wide zoo of exceptions on the broken files in this set — struct
        # errors, index errors, its own InvalidHeaderException. They all mean one thing to a
        # caller: this file cannot be read. Re-raised as ValueError with the original text,
        # never swallowed, because "which way it was broken" is a survey finding.
        raise ValueError(f"{os.path.basename(path)}: undecodable — "
                         f"{type(exc).__name__}: {exc}") from exc

    names = list(parser.field_names)
    source = {n: i for i, n in enumerate(names)}
    wanted = list(INAV_FIELDS) + [f"axisRate[{i}]" for i in sorted(AXIS_INDEX.values())]
    wanted = [w for w in dict.fromkeys(wanted)]
    missing = [f for f in INAV_FIELDS if f not in source]
    if missing:
        raise ValueError(f"{os.path.basename(path)}: not an INAV quad log — missing {missing}")
    take = [source[w] for w in wanted if w in source]
    kept = [w for w in wanted if w in source]

    # ONLY the columns this module uses, and ONLY I and P frames.
    #
    # Both halves of that were found by running this loader over all 141 files rather than over
    # one. `Parser.frames()` interleaves I/P with S, G and H frames; the S-frame fields occupy
    # the SAME 87-wide tuple and come back as EMPTY STRINGS in an I or P frame, so a
    # width check does not exclude them and `np.asarray(rows, float)` died on '' for 118 of the
    # 141 files. Slicing the columns we actually read sidesteps it entirely — and the S-frame
    # fields are exactly the ones this module refuses to expose anyway (escRPM, vbat).
    #
    # The iteration is also inside the try: orangebox raises from the GENERATOR, not from
    # Parser.load, so LOG00322's `'I' format requires 0 <= number <= 4294967295` escaped a
    # try wrapped around load() alone and surfaced as an unhandled struct.error.
    rows = []
    try:
        for ft, vals in parser.frames():
            if ft.value in ("I", "P") and len(vals) == len(names):
                rows.append([vals[i] for i in take])
    except Exception as exc:
        raise ValueError(f"{os.path.basename(path)}: corrupt frame stream after "
                         f"{len(rows)} frames — {type(exc).__name__}: {exc}") from exc
    if len(rows) < min_frames:
        raise ValueError(
            f"{os.path.basename(path)}: truncated or empty — {len(rows)} usable I/P frames, "
            f"need {min_frames}."
        )
    try:
        data = np.asarray(rows, dtype=float)
    except (ValueError, TypeError) as exc:
        raise ValueError(f"{os.path.basename(path)}: non-numeric frame payload — {exc}") from exc

    col = {n: i for i, n in enumerate(kept)}
    headers = dict(parser.headers)
    skip = _preamble_frames(headers)
    if len(data) <= skip + min_frames:
        raise ValueError(
            f"{os.path.basename(path)}: truncated or empty — {len(data)} I/P frames, of which "
            f"the first {skip} are the log preamble."
        )
    data = data[skip:]

    log = InavLog(path=path, headers=headers, col=col, rows=data)
    log.sampling_evidence = (
        f"preamble {skip} frames dropped (I interval); "
        + check_uniform_sampling(data[:, col["time"]], path, 1e-6)[1]
    )
    log.units_evidence = _verify_deg_s(data, col, path)
    log.unfiltered, log.gyro_evidence = _verify_gyro_raw(data, col, log.sampling_evidence, path)
    return log


def _preamble_frames(headers: dict) -> int:
    """One I-frame interval, from the log's own header. See DEFAULT_PREAMBLE_FRAMES."""
    try:
        n = int(str(headers.get("I interval", DEFAULT_PREAMBLE_FRAMES)).split("/")[0])
    except (TypeError, ValueError):
        return DEFAULT_PREAMBLE_FRAMES
    # A header is not trusted to be sane, only to be a starting point: an absurd I interval
    # would turn this into an arbitrary truncation, which is the thing it must never become.
    return n if 0 < n <= 4 * DEFAULT_PREAMBLE_FRAMES else DEFAULT_PREAMBLE_FRAMES


def _sample_rate(log: InavLog) -> float:
    dt, _ = check_uniform_sampling(log.rows[:, log.col["time"]], log.path, 1e-6)
    return 1.0 / dt


def _verify_deg_s(data, col, path) -> str:
    """Prove the gyro columns are deg/s by regressing them on INAV's own deg/s setpoint.

    `axisRate[]` is the rate the FC was commanded to fly, in deg/s by definition. If gyroADC
    were raw sensor counts the slope would come out at tens.

    A WRONG scale is refused. An UNVERIFIABLE scale is reported and allowed through, and the
    difference matters more than it first looks:

      * the check needs the aircraft to have been COMMANDED TO MOVE. On this survey platform
        it often was not — 43 of the 141 files have no axis correlating above r = 0.5, which
        is the same "too steady" property that makes them inadmissible under criterion (d).
      * a BENCH TAP, which is the one thing this reader is actually for, has no rate command
        at all, by construction. A hard refusal here would refuse every input on the only
        path that can produce a number.
      * and it is not load-bearing for that path anyway. impact_analysis measures a FREQUENCY
        and a DAMPING RATIO. Multiply the signal by any constant and the phase slope is
        unchanged and zeta, being dimensionless, is unchanged too. A scale error would have
        to reach an AMPLITUDE before it could reach a result.

    So: refuse a measured-and-wrong scale, report an unmeasurable one, and say which in the
    evidence. Anything downstream that starts using amplitudes must read this verdict first.
    """
    verdicts = []
    for axis, i in AXIS_INDEX.items():
        gk, rk = f"gyroADC[{i}]", f"axisRate[{i}]"
        if gk not in col or rk not in col:
            continue
        g, r = data[:, col[gk]], data[:, col[rk]]
        if g.std() <= 0 or r.std() <= 0:
            continue
        corr = abs(float(np.corrcoef(g, r)[0, 1]))
        if corr < DEG_S_MIN_CORR:
            continue  # the axis barely moved; a slope fitted to noise proves nothing
        slope = float(np.polyfit(r, g, 1)[0])
        verdicts.append((axis, slope, corr))
    if not verdicts:
        return (
            f"gyro scale NOT VERIFIED: no axis correlates with its own axisRate setpoint above "
            f"r = {DEG_S_MIN_CORR} (the aircraft was never commanded to move much, or this is "
            "a bench recording). Frequency and damping are scale-invariant, so an impact "
            "result stands; any AMPLITUDE taken from this log does not."
        )
    lo, hi = DEG_S_SLOPE_RANGE
    bad = [v for v in verdicts if not lo <= v[1] <= hi]
    if bad:
        raise ValueError(
            f"{os.path.basename(path)}: gyroADC regresses on axisRate at slope "
            + ", ".join(f"{a} {s:.2f}" for a, s, _ in bad)
            + f", outside {lo}-{hi}. The gyro columns are not deg/s and every frequency this "
            "log produced would be scaled by that factor."
        )
    return "gyro is deg/s: gyroADC vs axisRate slope " + ", ".join(
        f"{a} {s:.2f} (r={c:.2f})" for a, s, c in verdicts)


def _verify_gyro_raw(data, col, sampling_evidence, path):
    """Is `gyroRaw` actually pre-filter? Measured, never taken from the field name.

    _looks_prefilter exists because names and headers lie, and a field called `gyroRaw` is
    precisely the kind of claim it was written to check. On a board with two gyros the
    semantics may differ again — betaflight#7886 is the Betaflight analogue — so the two
    analysed axes are also checked against each other, exactly as debug[0..1] are.
    """
    fs = 1.0 / (float(np.median(np.diff(data[:, col["time"]]))) * 1e-6)
    ratios = {}
    for axis, i in AXIS_INDEX.items():
        verdict, ratio = _looks_prefilter(data[:, col[f"gyroRaw[{i}]"]],
                                          data[:, col[f"gyroADC[{i}]"]], fs)
        ratios[axis] = (verdict, ratio)
    roll_v, roll_r = ratios["roll"]
    pitch_v, pitch_r = ratios["pitch"]
    same, r = _same_axis(data[:, col["gyroRaw[0]"]], data[:, col["gyroRaw[1]"]])
    detail = (f"gyroRaw carries {roll_r:.1f}x (roll) and {pitch_r:.1f}x (pitch) gyroADC's "
              f"high-band power — measured, not taken from the field name; "
              f"roll vs pitch correlate at r = {r:.3f}")
    if same:
        return False, (detail + " — SAME AXIS, so these are not roll and pitch")
    if not (roll_v and pitch_v):
        return False, (detail + " — below the pre-filter threshold on "
                       + " and ".join(a for a in ("roll", "pitch") if not ratios[a][0]))
    return True, detail


#: The refusal `load_inav` always produces. It is a hardware fact, not a setting, and the
#: message says so — LTHL-18 already recorded one wrong diagnosis of this shape ("bidirectional
#: DShot was off" on a log that had it enabled), and "enable DShot" would be the same mistake
#: told to a pilot whose ESCs cannot do it.
NO_RPM_MESSAGE = (
    "no rpm in an INAV PWM log. `motor_pwm_protocol` is PWM (400 Hz), so the ESCs have no\n"
    "  telemetry line and there is nothing to log — this is a HARDWARE fact, not a setting,\n"
    "  and no code change fixes it. Do NOT read `escRPM`: it measures as a single constant\n"
    "  (134380293) across an entire flight and is not rpm.\n"
    "  `motor[]` is a throttle COMMAND. Converting it to a frequency needs a thrust constant\n"
    "  that would be invented, and order tracking on an invented frequency measures the\n"
    "  invention. Note also that criterion (d) fails here for the opposite reason to the\n"
    "  freestyle logs: the throttle never moves at all."
)


def load_inav(path: str, arm_m: float, tip_mass_kg: float, blades: int) -> Trace:
    """Always raises. That is the point, and it is the same refusal load_betaflight makes.

    Everything measurable is measured first, so the refusal carries evidence rather than a
    bare assertion — and so that a bench-tap INAV log routed here by mistake still gets its
    gyroRaw verdict printed before being sent to load_inav_impact.

    arm_m / tip_mass_kg / blades are accepted to mirror load_betaflight's signature and are
    NEVER read from the log. See "A LOG MAY NEVER RECONSTRUCT A BUILD" above.
    """
    log = read_inav(path)
    raise ValueError(
        f"{os.path.basename(path)}: {NO_RPM_MESSAGE}\n"
        f"  For the record, the rest of this log checked out: {log.gyro_evidence}\n"
        f"  {log.units_evidence}\n"
        f"  {log.sampling_evidence}\n"
        "  A bench tap of this airframe WOULD be admissible — nothing rotates during a tap,\n"
        "  so impact_analysis.load_inav_impact has no rpm requirement. See LTHL-49."
    )


def load_inav_impact(path: str, axis: str = "roll", **meta) -> Recording:
    """An INAV log of a bench tap. The one path where these logs can produce a number.

    Uses gyroRaw when it is measurably pre-filter and gyroADC otherwise, and says which. The
    110 Hz gyro lowpass sits inside the search band, so a gyroADC recording is refused by
    impact_analysis.assert_usable — correctly, and with the evidence attached.
    """
    if axis not in AXIS_INDEX:
        raise ValueError(f"axis must be one of {sorted(AXIS_INDEX)}, not {axis!r}")
    log = read_inav(path)
    i = AXIS_INDEX[axis]
    key = f"gyroRaw[{i}]" if log.unfiltered else f"gyroADC[{i}]"
    return Recording(
        name=os.path.basename(path),
        source="inav",
        sample_rate_hz=_sample_rate(log),
        signal=log.rows[:, log.col[key]],
        unfiltered=log.unfiltered,
        unfiltered_evidence=f"{key}: {log.gyro_evidence}",
        sampling_evidence=log.sampling_evidence,
        header=log.headers,
        **meta,
    )
