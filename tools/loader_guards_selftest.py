"""Check on the two ADMISSIBILITY guards the blackbox loaders apply (LTHL-18).

Not evidence about the model, and not evidence about the analysis either. Evidence that the
loaders REFUSE input they cannot honestly measure:

  1. NON-UNIFORM SAMPLING. Every loader takes its sample rate from median(diff(t)) and then
     hands the samples to an FFT as if they were contiguous. A gapped log yields a plausible
     median, so the time axis silently compresses and the frequency comes out wrong with
     nothing in the output to say so. resonance_analysis.check_uniform_sampling refuses it.
  2. debug[1] RETURNED ON FAITH. _choose_gyro_columns measured debug[0] and returned
     debug[0..1], never touching debug[1]. On a dual-gyro board (betaflight#7886) debug[]
     carries the same axis from two sensors, so debug[0] passes honestly and the tool analyses
     roll twice while labelling one of them pitch.

Every section here ends by DEMONSTRATING THAT IT COULD FAIL — the guard is bypassed and the
wrong answer it would have let through is printed. A green suite that would be green without
the fix is the failure mode this project keeps catching in itself (LTHL-18's synthetic sweep).

Real data. Oscar Liang's 4.3.1 practice log is the regression case and is NOT vendored into the
repo, per validation.md's cite-don't-vendor rule; if it is absent those sections are SKIPPED
loudly rather than passed quietly. The gapped and dual-gyro cases are DERIVED from it by
deleting rows and by overwriting a column — they are INJECTED defects in a real file, not
logs captured from defective hardware. No claim is made here that either guard has been tested
against a genuinely gapped log off real hardware; none has been obtained.

Run: .venv/bin/python tools/loader_guards_selftest.py
"""
import os
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import impact_analysis as ia  # noqa: E402
import resonance_analysis as ra  # noqa: E402

OSCAR = os.path.expanduser("~/Desktop/OneWeekendAI/logs/oscar_4s_5in_freestyle.csv")

failures = []
skipped = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print(f"    *** FAILED: {message}")
    return condition


def refuses(fn, *args, **kw):
    """Returns (was_refused, message). A guard that refuses must SAY WHAT IT MEASURED."""
    try:
        fn(*args, **kw)
    except ValueError as exc:
        return True, str(exc)
    return False, ""


# ---------------------------------------------------------------------------
# Fixtures: a blackbox CSV we control, and derivations of Oscar's real one.
# ---------------------------------------------------------------------------

FS = 2000.0
TMP = tempfile.mkdtemp(prefix="loader_guards_")


def write_bbl(path, t_us, channels):
    """A minimal blackbox_decode-shaped CSV: 'H key,value' lines, quoted names, then rows."""
    names = ["time"] + list(channels)
    with open(path, "w") as fh:
        fh.write("H Craft name,selftest\n")
        fh.write("H debug_mode,6\n")
        fh.write(",".join(f'"{n}"' for n in names) + "\n")
        cols = [np.asarray(t_us, dtype=float)] + [np.asarray(channels[n], dtype=float)
                                                  for n in channels]
        for row in np.column_stack(cols):
            fh.write(",".join(f"{v:.6f}" for v in row) + "\n")
    return path


def lowpass(x, fc=60.0, poles=4):
    """A 4-pole lowpass, standing in for the gyro lowpass and notches a real log's gyroADC has
    been through.

    It has to be a REAL filter, and how real took two tries to get right. _looks_prefilter
    compares the FRACTION of AC power in 100-800 Hz, so a gentle filter that attenuates the
    whole signal roughly evenly changes almost nothing: a 4-tap moving average measured 1.04x
    and one pole at 60 Hz measured 1.35x, both of which the 3x threshold correctly refused.
    Four poles measures 19.3x — the same order as the 63.6x Oscar's real log shows, which is
    the point: a fixture claiming to be a filtered channel has to actually look like one.
    """
    a = 1.0 - np.exp(-2.0 * np.pi * fc / FS)
    for _ in range(poles):
        y = np.empty_like(x)
        acc = 0.0
        for i, v in enumerate(x):
            acc += a * (v - acc)
            y[i] = acc
        x = y
    return x


def planted_ringdown(hz, zeta, seconds, strikes=6, rng=np.random.default_rng(11)):
    """Taps exciting one mode. Same shape impact_analysis_selftest.ringdown builds."""
    t = np.arange(0, seconds, 1.0 / FS)
    x = 0.02 * rng.standard_normal(len(t))
    gap = seconds / (strikes + 1)
    for s in range(strikes):
        i0 = int((0.15 + s * gap) * FS)
        rel = t[i0:] - t[i0]
        x[i0:] += np.exp(-zeta * 2 * np.pi * hz * rel) * np.sin(
            2 * np.pi * hz * rel + rng.uniform(0, 2 * np.pi))
    return t, x


def synthetic_log(path, hz=185.0, zeta=0.03, seconds=5.0, drop=None):
    """A synthetic blackbox log with a mode planted at `hz`.

    `drop` is a list of (start, count) row slices TO DELETE — timestamps included, which is
    exactly what a dropped blackbox frame looks like: the survivors keep their true times and
    the file simply has fewer of them.

    WHERE the holes go decides what the defect does, and this took three fixtures to pin down:

      * ONE BIG HOLE between two taps deletes whole strikes and leaves every surviving ringdown
        intact. The analyser returns the right answer from the strikes that are still whole.
      * A BURST INSIDE EACH DECAY (`drop_in_decay`) wrecks the envelope so thoroughly that the
        R^2 gate throws every fit away and NO mode is returned. It fails safe, by luck.
      * REGULAR DROPS (`drop_every`) are the dangerous one, and are what a card that cannot
        quite keep up actually produces. The survivors are still a clean decaying sinusoid,
        just with the time axis compressed by the dropped fraction, so every fit succeeds and
        the frequency comes out scaled by 1/(1-fraction) with nothing anywhere to say so.

    All three are refused identically by the guard. Only the third demonstrates WHY, so it is
    the one section 1f uses — but the first two are why the guard cannot be replaced by "the
    analysis would have noticed": twice out of three times it does not notice, and once out of
    three it hands back a confident wrong number.
    """
    t, x = planted_ringdown(hz, zeta, seconds)
    _, y = planted_ringdown(hz * 1.31, zeta, seconds, rng=np.random.default_rng(29))
    t_us = t * 1e6
    chans = {
        "gyroADC[0]": lowpass(x),
        "gyroADC[1]": lowpass(y),
        "gyroADC[2]": np.zeros_like(x),
        "debug[0]": x,
        "debug[1]": y,
        "debug[2]": np.zeros_like(x),
        "debug[3]": np.zeros_like(x),
    }
    if drop:
        keep = np.ones(len(t_us), dtype=bool)
        for start, count in drop:
            keep[start:start + count] = False
        t_us = t_us[keep]
        chans = {k: v[keep] for k, v in chans.items()}
    return write_bbl(path, t_us, chans)


def drop_in_decay(seconds, strikes=6, after_ms=8.0, lost_ms=60.0):
    """Row slices that punch a burst-shaped hole into each tap's ringdown."""
    gap = seconds / (strikes + 1)
    return [(int((0.15 + s * gap + after_ms / 1000.0) * FS), int(lost_ms / 1000.0 * FS))
            for s in range(strikes)]


def drop_every(n, rows):
    """Every n-th row gone: a fifth of the frames lost, evenly. diff(t) is 500,500,500,1000
    repeating, so the MEDIAN is still exactly 500 us and the old code never notices."""
    return [(i, 1) for i in range(0, rows, n)]


def derive_from_oscar(path, drop=None, copy_column=None):
    """Rewrite Oscar's real log with one defect injected. Text in, text out — nothing is
    re-derived, so anything that still passes passed on the real file's own numbers."""
    with open(OSCAR) as fh:
        lines = fh.readlines()
    head = [ln for ln in lines if not ln.startswith('"')][:0]  # placeholder, filled below
    head, names_line, data = [], None, []
    for ln in lines:
        if names_line is None and ln.startswith('"'):
            names_line = ln
            continue
        (data if names_line is not None else head).append(ln)
    names = [c.strip().strip('"') for c in names_line.split(",")]
    if drop is not None:
        start, count = drop
        data = data[:start] + data[start + count:]
    if copy_column is not None:
        # `copy_column` = (destination, source, noise_counts). The dual-gyro injection copies
        # debug[0] into debug[1] with a little noise on top: two gyros on one axis see the same
        # motion but are not the same chip, so an equality test would be answering an easier
        # question than the real one. Noise is in deg/s; 25 deg/s against this log's own
        # roll amplitude leaves r at ~0.98, i.e. two clearly distinguishable copies of one axis
        # rather than a degenerate r = 1.000.
        dst, src, noise = copy_column
        i_dst, i_src = names.index(dst), names.index(src)
        rng = np.random.default_rng(17)
        out = []
        for ln in data:
            cells = ln.rstrip("\n").split(",")
            cells[i_dst] = f"{float(cells[i_src]) + noise * rng.standard_normal():.4f}"
            out.append(",".join(cells) + "\n")
        data = out
    with open(path, "w") as fh:
        fh.writelines(head + [names_line] + data)
    return path


# ---------------------------------------------------------------------------
# Guard 1 — non-uniform sampling
# ---------------------------------------------------------------------------

print("--- guard 1a: the clean log passes, and its measured jitter is reported ---")
if not os.path.exists(OSCAR):
    skipped.append(f"guard 1a/1b/1c/2b: {OSCAR} not present (cite-don't-vendor; see docstring)")
    print(f"    SKIPPED: {OSCAR} not found")
    oscar_clean = None
else:
    oscar_clean = ia.load_betaflight_impact(OSCAR, arm="A")
    print(f"    {oscar_clean.sampling_evidence}")
    print(f"    {oscar_clean.unfiltered_evidence}")
    check(oscar_clean.sample_rate_hz > 0, "clean log did not load")
    # THE REAL-JITTER CASE. This log is not synthetic and not smoothed: if the limit were tight
    # enough to trip on scheduler variance, it would trip here, on 194087 rows of real flight.
    worst = float(oscar_clean.sampling_evidence.split("worst gap ")[1].split("x")[0])
    check(worst < ra.GAP_RATIO_LIMIT,
          f"the clean log's own jitter ({worst:.3f}x) trips the guard — it is useless in the field")
    print(f"    real-flight jitter {worst:.3f}x vs limit {ra.GAP_RATIO_LIMIT:.1f}x "
          f"({(ra.GAP_RATIO_LIMIT - 1) / (worst - 1):.0f}x headroom)")

print("\n--- guard 1b: one deleted row is a dropped frame, and must be refused ---")
if oscar_clean is not None:
    one = derive_from_oscar(os.path.join(TMP, "oscar_one_dropped.csv"), drop=(50000, 1))
    got, msg = refuses(ia.load_betaflight_impact, one, arm="A")
    check(got, "a single dropped frame was accepted; the guard cannot see the smallest defect")
    if got:
        print("   ", msg.splitlines()[0].split(": ", 1)[1])
        check("2.0x" in msg or "worst is 2" in msg, "the refusal did not report the measured ratio")

print("\n--- guard 1c: a real stall (a run of rows gone) is refused, both tools ---")
if oscar_clean is not None:
    stalled = derive_from_oscar(os.path.join(TMP, "oscar_stall.csv"), drop=(80000, 4000))
    for label, fn, kw in (
        ("impact_analysis.load_betaflight_impact", ia.load_betaflight_impact, {"arm": "A"}),
        ("resonance_analysis.load_betaflight", ra.load_betaflight,
         {"arm_m": 0.110, "tip_mass_kg": 0.0365, "blades": 3, "pole_pairs": 7}),
    ):
        got, msg = refuses(fn, stalled, **kw)
        check(got, f"{label} accepted a log with 4000 rows missing")
        if got:
            check("NON-UNIFORM SAMPLING" in msg,
                  f"{label} refused for the wrong reason: {msg.splitlines()[0]}")
            print(f"    {label}: refused, {msg.splitlines()[0].split('— ')[1]}")

print("\n--- guard 1d: jitter far worse than any real log is still NOT refused ---")
# +-20% random jitter, an order of magnitude beyond the 2.7% a real 2 kHz log shows, and still
# not a missing sample. The guard must let it through: it detects holes, not raggedness.
rng = np.random.default_rng(3)
jittered = np.cumsum(500.0 * (1.0 + rng.uniform(-0.2, 0.2, 20000)))
dt, ev = ra.check_uniform_sampling(jittered, "jitter", 1e-6)
print(f"    {ev}")
check(abs(dt - 500e-6) / 500e-6 < 0.02, f"jittered dt came out at {dt * 1e6:.1f} us")

print("\n--- guard 1e: monotonicity. A duplicated or reversed timestamp is corruption ---")
back = np.arange(20000, dtype=float) * 500.0
back[9000] = back[9001] + 10.0
got, msg = refuses(ra.check_uniform_sampling, back, "reversed", 1e-6)
check(got, "time running backwards was accepted")
if got:
    print("   ", msg.splitlines()[0].split(": ", 1)[1])

print("\n--- guard 1g: the two LOTHAL loaders, which take their rate from the HEADER ---")
# A Lothal log states sample_rate_hz in its header, so the gap check is not what produces the
# rate there — it is what stops the header's claim being believed over the rows the FFT will
# actually see. Same class of gap between claim and data that _looks_prefilter exists for.
# No real FlightRecorder log is on disk, so this is a synthetic in that file's exact shape.
LOTHAL_COLS = ["t_s", "gyro_x_rad_s", "gyro_y_rad_s", "gyro_z_rad_s",
               "m1_rpm", "m2_rpm", "m3_rpm", "m4_rpm"]


def write_lothal(path, n=8000, fs=1000.0, drop=None):
    t = np.arange(n) / fs
    _, x = planted_ringdown(185.0, 0.03, n / fs)
    x = np.interp(t, np.arange(len(x)) / FS, x) / ra.RAD_TO_DEG
    rpm = np.full(n, 9000.0)
    cols = [t, x, np.zeros(n), x * 0.5, rpm, rpm, rpm, rpm]
    if drop:
        keep = np.ones(n, dtype=bool)
        for start, count in drop:
            keep[start:start + count] = False
        cols = [c[keep] for c in cols]
    with open(path, "w") as fh:
        fh.write('#{"aircraft": {"fingerprint": "selftest"}, "sample_rate_hz": %g,\n' % fs)
        fh.write('# "gyro": {"lowpass_hz": 0}}\n')
        fh.write(",".join(LOTHAL_COLS) + "\n")
        for row in np.column_stack(cols):
            fh.write(",".join(f"{v:.9g}" for v in row) + "\n")
    return path


lothal_clean = write_lothal(os.path.join(TMP, "lothal_clean.csv"))
lothal_gapped = write_lothal(os.path.join(TMP, "lothal_gapped.csv"), drop=[(3000, 900)])
for label, fn, kw in (
    ("resonance_analysis.load_lothal", ra.load_lothal, {"blades": 3}),
    ("impact_analysis.load_lothal_impact", ia.load_lothal_impact, {}),
):
    ok = fn(lothal_clean, **kw)
    print(f"    {label}: {ok.sampling_evidence}")
    check(ok.sample_rate_hz == 1000.0, f"{label} lost the header sample rate")
    got, msg = refuses(fn, lothal_gapped, **kw)
    check(got and "NON-UNIFORM SAMPLING" in msg, f"{label} accepted a gapped Lothal log")

print("\n--- guard 1f: THE CHECK THAT THE CHECK CAN FAIL ---")
print("    Bypass the guard and the gapped log returns a number. Here is the number.")
PLANTED = 185.0
clean_path = synthetic_log(os.path.join(TMP, "synth_clean.csv"))
# One frame in five lost, evenly — the pattern that produces a WRONG NUMBER rather than no
# number. See synthetic_log's docstring for the two fixtures that came before this one.
gapped_path = synthetic_log(os.path.join(TMP, "synth_gapped.csv"),
                            drop=drop_every(5, int(5.0 * FS)))
burst_path = synthetic_log(os.path.join(TMP, "synth_burst.csv"), drop=drop_in_decay(5.0))

rec_clean = ia.load_betaflight_impact(clean_path, arm="A")
groups_clean, _ = ia.analyse(rec_clean)
hit_clean = next((g for g in groups_clean if abs(g.hz - PLANTED) <= 0.06 * PLANTED), None)
check(hit_clean is not None, f"the synthetic control lost its own planted {PLANTED} Hz mode")
if hit_clean:
    print(f"    with the guard, clean log : {hit_clean.hz:6.2f} Hz  zeta {hit_clean.zeta:.4f} "
          f"(planted {PLANTED:.0f} Hz, zeta 0.0300)")

for label, p in (("gapped", gapped_path), ("burst ", burst_path)):
    got, msg = refuses(ia.load_betaflight_impact, p, arm="A")
    check(got, f"the synthetic {label.strip()} log was accepted")
    if got:
        print(f"    with the guard, {label} log: REFUSED — {msg.splitlines()[0].split('— ')[1]}")

# Now revert the guard, exactly as deleting it would: median(diff(t)) and no questions asked.
original = ra.check_uniform_sampling
ra.check_uniform_sampling = lambda t, name, unit: (
    float(np.median(np.diff(np.asarray(t, dtype=float)))) * unit, "GUARD REVERTED")
ia.check_uniform_sampling = ra.check_uniform_sampling
try:
    bypassed = {}
    for label, p in (("gapped", gapped_path), ("burst", burst_path)):
        groups_bad, _ = ia.analyse(ia.load_betaflight_impact(p, arm="A"))
        bypassed[label] = next((g for g in groups_bad if 60.0 <= g.hz <= 600.0), None)
finally:
    ra.check_uniform_sampling = original
    ia.check_uniform_sampling = original

hit_bad = bypassed["gapped"]
if hit_bad is None:
    check(False, "the reverted run on the gapped log returned nothing, so this section proves "
                 "nothing — rebuild the fixture until the bypass produces a WRONG NUMBER")
else:
    err = (hit_bad.hz - PLANTED) / PLANTED
    print(f"    without the guard, gapped : {hit_bad.hz:6.2f} Hz  zeta {hit_bad.zeta:.4f}"
          f"   <-- {err:+.1%} on frequency, and it looks completely normal")
    check(abs(err) > ia.IMPACT_AGREEMENT_FRACTION,
          f"bypassing the guard changed nothing worth catching ({err:+.1%}) — the gapped "
          "fixture is too gentle to prove the guard earns its place")
    # Honest about WHICH number went wrong. A fifth of the samples removed EVENLY compresses
    # the time axis by 1/(1-1/5) = 1.25, and zeta is dimensionless — frequency and decay rate
    # scale together — so the damping survives and only the frequency lies. The damping is the
    # casualty in the burst case below, where the envelope itself is the thing with a hole in it.
    print(f"{'':32s}(zeta is dimensionless, so an even 20% drop scales f and the decay rate "
          f"together and leaves it at {hit_bad.zeta:.4f})")
burst_bad = bypassed["burst"]
print(f"    without the guard, burst  : "
      + ("no mode returned at all — this one fails safe, by luck"
         if burst_bad is None else f"{burst_bad.hz:6.2f} Hz  zeta {burst_bad.zeta:.4f}"))

# ---------------------------------------------------------------------------
# Guard 2 — debug[1]
# ---------------------------------------------------------------------------

print("\n--- guard 2a: two real axes are accepted, and the correlation is reported ---")
h, names, rows = ra._read_bbl_csv(clean_path)
colmap = {n: i for i, n in enumerate(names)}
unf, ev, rk, pk = ra._choose_gyro_columns(h, colmap, rows, FS)
print(f"    {ev}")
check(unf and (rk, pk) == ("debug[0]", "debug[1]"),
      f"a two-axis pre-filter log was not accepted: {ev}")
check("correlate at r" in ev, "the accepted evidence does not report the measured correlation")

print("\n--- guard 2b: and on the real log, unchanged ---")
if oscar_clean is not None:
    check(oscar_clean.unfiltered, "Oscar's log stopped being recognised as pre-filter")
    check("debug[0..1]" in oscar_clean.unfiltered_evidence,
          f"Oscar's log no longer selects debug[0..1]: {oscar_clean.unfiltered_evidence}")

print("\n--- guard 2c: debug[1] carrying the SAME AXIS as debug[0] is refused ---")
same_path = os.path.join(TMP, "synth_same_axis.csv")
_, x = planted_ringdown(PLANTED, 0.03, 5.0)
write_bbl(same_path, np.arange(len(x)) * (1e6 / FS), {
    "gyroADC[0]": lowpass(x),
    "gyroADC[1]": lowpass(x),
    "debug[0]": x,
    # The dual-gyro case: the second sensor on the SAME axis. Not a copy — its own noise, which
    # is why a correlation test and not an equality test is the right question to ask.
    "debug[1]": x + 0.01 * np.random.default_rng(5).standard_normal(len(x)),
})
h2, names2, rows2 = ra._read_bbl_csv(same_path)
col2 = {n: i for i, n in enumerate(names2)}
unf2, ev2, rk2, pk2 = ra._choose_gyro_columns(h2, col2, rows2, FS)
print(f"    {ev2}")
check(not unf2, "a same-axis debug[] pair was accepted as roll and pitch")
check("ONE physical axis" in ev2, f"refused for the wrong reason: {ev2}")
if oscar_clean is not None:
    real_same = derive_from_oscar(os.path.join(TMP, "oscar_same_axis.csv"),
                                  copy_column=("debug[1]", "debug[0]", 25.0))
    h3, names3, rows3 = ra._read_bbl_csv(real_same)
    col3 = {n: i for i, n in enumerate(names3)}
    unf3, ev3, _, _ = ra._choose_gyro_columns(h3, col3, rows3, oscar_clean.sample_rate_hz)
    print(f"    (real log, debug[1] := debug[0] + noise) {ev3}")
    check(not unf3, "the real log with a same-axis debug[1] was accepted")
    check("ONE physical axis" in ev3,
          "the real dual-gyro injection was refused, but by the pre-filter check rather than "
          f"the axis check — so it does not exercise guard 2's new half: {ev3}")

print("\n--- guard 2d: debug[1] that is NOT pre-filter is refused, even though debug[0] is ---")
half_path = os.path.join(TMP, "synth_half_filtered.csv")
_, y = planted_ringdown(PLANTED * 1.31, 0.03, 5.0, rng=np.random.default_rng(29))
write_bbl(half_path, np.arange(len(x)) * (1e6 / FS), {
    "gyroADC[0]": lowpass(x),
    "gyroADC[1]": lowpass(y),
    "debug[0]": x,
    "debug[1]": lowpass(y),  # post-filter, same as gyroADC[1]
})
h4, names4, rows4 = ra._read_bbl_csv(half_path)
col4 = {n: i for i, n in enumerate(names4)}
unf4, ev4, _, _ = ra._choose_gyro_columns(h4, col4, rows4, FS)
print(f"    {ev4}")
check(not unf4, "debug[1] being post-filter was not caught; the pitch axis would be filtered")

print("\n--- guard 2e: THE CHECK THAT THE CHECK CAN FAIL ---")
print("    Revert to measuring debug[0] alone and the same-axis log is accepted as two axes.")
verdict_only_0, ratio0 = ra._looks_prefilter(rows2[:, col2["debug[0]"]],
                                             rows2[:, col2["gyroADC[0]"]], FS)
print(f"    debug[0] alone: pre-filter = {verdict_only_0}, at {ratio0:.1f}x gyroADC[0] — "
      "an honest measurement of a channel that really is unfiltered gyro")
check(verdict_only_0,
      "the same-axis fixture fails the OLD check too, so guard 2 is not what rejects it — "
      "the fixture proves nothing")
same_v, r_same = ra._same_axis(rows2[:, col2["debug[0]"]], rows2[:, col2["debug[1]"]])
diff_v, r_diff = ra._same_axis(rows[:, colmap["debug[0]"]], rows[:, colmap["debug[1]"]])
print(f"    r(same axis) = {r_same:.4f}   r(two axes) = {r_diff:.4f}   "
      f"limit = {ra.AXIS_DISTINCTNESS_LIMIT:.2f}")
check(same_v and not diff_v, "the correlation test does not separate the two fixtures")

print()
for s in skipped:
    print(f"SKIPPED: {s}")
if failures:
    print(f"SELF-TEST FAILED: {len(failures)} check(s)")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("SELF-TEST PASSED" + (" (with skips)" if skipped else ""))
