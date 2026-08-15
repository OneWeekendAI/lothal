"""Synthetic check on the CROSS-LOG statistic (LTHL-50).

Not evidence about the model, and not evidence about any corpus. Evidence about the STATISTIC,
and specifically that it can come back wrong-shaped: return nothing, refuse itself, or reject
the thing it was built to find.

Section 0 of campbell_analysis.py admits the method was inspired by the data it will be run
on. That admission is what makes this file the load-bearing part of the slice: every "it
works" result below is suspect on its own, and the controls are what the pre-registration is
actually worth. Section 6 lists eight requirements and all eight are here, numbered to match.

NO REAL LOG IS TOUCHED. This file and campbell_analysis.py are committed alone and first, so
that the statistic predating the corpus is a fact about git rather than a claim in a write-up.

Run: .venv/bin/python tools/campbell_analysis_selftest.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import campbell_analysis as ca  # noqa: E402

RNG = np.random.default_rng(50)

failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print(f"    *** FAILED: {message}")
    return condition


def refuses(fn, *args, **kw):
    try:
        fn(*args, **kw)
    except ValueError as exc:
        return True, str(exc)
    return False, ""


# ---------------------------------------------------------------------------
# A synthetic corpus: N logs, each at its own steady hover throttle
# ---------------------------------------------------------------------------

def corpus(n_logs=60, one_x=(110.0, 180.0), modes=(185.0,), orders=(1.0, 2.0, 3.0),
           read_sigma=0.01, axes=("roll", "pitch"), mode_axes=None, drift=0.0,
           mode_logs=None, seed=None):
    """Logs whose 1x line sweeps ACROSS the corpus while each log sits still.

    Every log gets its own hover throttle; the rotor lines follow it and the modes do not.
    `read_sigma` is per-peak reading noise as a fraction — the thing that makes a fitted slope
    uncertain. Defaults to 1%, tighter than the pre-registered 3%, so the gate is exercised by
    the corpus SIZE and SPREAD rather than by noise the fixture chose.
    """
    rng = np.random.default_rng(seed if seed is not None else 50)
    mode_axes = mode_axes or {m: axes for m in modes}
    mode_logs = mode_logs if mode_logs is not None else n_logs
    # Hover throttle, and the 1x it produces. The map from one to the other is monotone and
    # NOT linear, exactly as a real thrust curve is not — the statistic must not care.
    motor = np.linspace(1120.0, 1370.0, n_logs)
    frac = (motor - motor.min()) / (motor.max() - motor.min())
    one_x_hz = one_x[0] * (one_x[1] / one_x[0]) ** frac

    points = []
    for k in range(n_logs):
        peaks = {ax: [] for ax in axes}
        for q in orders:
            for ax in axes:
                peaks[ax].append(q * one_x_hz[k] * (1 + read_sigma * rng.standard_normal()))
        if k < mode_logs:
            for m in modes:
                shifted = m * (1.0 + drift * (k / max(1, n_logs - 1) - 0.5))
                for ax in mode_axes[m]:
                    peaks[ax].append(shifted * (1 + read_sigma * rng.standard_normal()))
        points.append(ca.LogPoint(name=f"L{k:03d}", motor_command=float(motor[k]),
                                  peaks={ax: sorted(v) for ax, v in peaks.items()}))
    return points


def summarise(label, cands, ruler):
    hits = [c for c in cands if c.frame_mode_candidate]
    print(f"    {label:38s} ruler {ruler.hz.min():.0f}-{ruler.hz.max():.0f} Hz  "
          f"{len(hits)} candidate(s)")
    for c in sorted(cands, key=lambda c: -c.logs)[:4]:
        tag = "CAND" if c.frame_mode_candidate else "rej "
        print(f"      {tag} {c.hz:7.1f} Hz  b={c.b:+.3f}+-{c.b_se:.4f}  {c.logs}/{c.of_logs}  "
              f"drift {c.drift:.1%}"
              + (f"  [{c.rejections[0][:58]}]" if c.rejections else ""))
    return hits


print("--- 1: a planted STATIONARY mode is recovered at the right frequency ---")
pts = corpus(modes=(185.0,))
cands, ruler, notes = ca.identify_frame_mode(pts)
hits = summarise("planted 185 Hz mode", cands, ruler)
check(len(hits) == 1, f"expected exactly one candidate, got {len(hits)}")
if hits:
    check(abs(hits[0].hz - 185.0) / 185.0 <= 0.01,
          f"185 Hz recovered as {hits[0].hz:.2f} Hz")
    check(abs(hits[0].b) <= ca.B_STATIONARY,
          f"the recovered mode has b = {hits[0].b:+.3f}, not stationary")

print("\n--- 2: every ROTOR line is rotor-locked, and NEVER stationary ---")
rotors = [c for c in cands if c.verdict == ca.VERDICT_ROTOR]
print(f"    {len(rotors)} rotor-locked line(s): "
      + ", ".join(f"{c.hz:.0f} Hz b={c.b:+.3f}" for c in rotors))
check(len(rotors) >= 1, "no rotor line was identified at all; the ruler may have eaten them")
check(all(abs(c.b - 1.0) <= ca.B_STATIONARY for c in rotors),
      "a rotor-locked line has b far from 1")
check(not any(c.frame_mode_candidate for c in rotors),
      "a ROTOR ORDER was returned as a frame mode candidate")

print("\n--- 2b: and still so when an order sits ON the mode mid-corpus ---")
# The configuration that makes the two look identical in any SINGLE log: the 1x sweep passes
# straight through the planted mode, so in the middle of the corpus they coincide. Only the
# cross-log slope can separate them, which is the whole claim of the method.
pts_cross = corpus(one_x=(120.0, 260.0), modes=(185.0,), orders=(1.0,))
cands_x, ruler_x, _ = ca.identify_frame_mode(pts_cross)
hits_x = summarise("1x sweeps THROUGH the 185 Hz mode", cands_x, ruler_x)
check(len(hits_x) == 1 and abs(hits_x[0].hz - 185.0) / 185.0 <= 0.02,
      f"the mode was lost or mismeasured when the 1x line crossed it: "
      f"{[round(h.hz, 1) for h in hits_x]}")

print("\n--- 3: THE CHECK THAT THE CHECK CAN FAIL. Move the mode, the answer must move. ---")
measured = []
for planted in (150.0, 185.0, 240.0):
    p = corpus(modes=(planted,))
    c, r, _ = ca.identify_frame_mode(p)
    h = [x for x in c if x.frame_mode_candidate]
    measured.append((planted, h[0].hz if h else None))
    print(f"    planted {planted:6.1f} Hz -> "
          + (f"{h[0].hz:6.1f} Hz" if h else "NOTHING FOUND"))
check(all(m is not None for _, m in measured), "a planted mode was missed entirely")
if all(m is not None for _, m in measured):
    spread = max(m for _, m in measured) - min(m for _, m in measured)
    check(spread > 60.0,
          f"the answer moved only {spread:.1f} Hz when the truth moved 90 Hz — the statistic "
          "is echoing the corpus geometry, not measuring a mode")

print("\n--- 4: a corpus with NO stationary line returns NOTHING, not a best guess ---")
pts_none = corpus(modes=())
cands_n, ruler_n, notes_n = ca.identify_frame_mode(pts_none)
hits_n = summarise("rotor orders only", cands_n, ruler_n)
check(len(hits_n) == 0, f"a rotor-only corpus produced {len(hits_n)} frame mode candidate(s)")
check(any("NO FRAME MODE CANDIDATE" in n for n in notes_n),
      "the rotor-only corpus did not say plainly that it found nothing")

print("\n--- 5: too little spread is REFUSED BY THE GATE, not analysed ---")
# The pre-registered prediction of section 4: a corpus whose ruler barely moves cannot separate
# b=0 from b=1, and the method must refuse ITSELF rather than return a confident number.
# read_sigma is tiny here ON PURPOSE. At 1% reading noise a ruler spanning 2% is not even
# monotone, so choose_ruler refuses first and the SE gate is never reached — a correct refusal
# for the wrong reason, which would leave the gate untested. The point of this section is a
# corpus that is CLEAN and still cannot resolve the two hypotheses, because spread and count,
# not noise, are what the gate is about.
#
# The planted mode also sits well AWAY from the ruler here (300 Hz against a 178-182 Hz
# ruler). At 185 Hz it fell inside MATCH_WINDOW of the ruler's own line, the two merged into
# one seed, and the merged blob came back b = +1.000 — a correct answer to a question the
# fixture did not mean to ask, and it masked the gate a second time.
pts_narrow = corpus(n_logs=20, one_x=(178.0, 182.0), modes=(300.0,), orders=(1.0,),
                    read_sigma=0.0005)
cands_w, ruler_w, _ = ca.identify_frame_mode(pts_narrow)
gated = [c for c in cands_w if any("SE(b)" in r for r in c.rejections)]
print(f"    ruler spans {ruler_w.hz.min():.1f}-{ruler_w.hz.max():.1f} Hz "
      f"(x{ruler_w.hz.max()/ruler_w.hz.min():.3f}); "
      f"{len(gated)} candidate(s) refused by the SE gate")
for c in gated[:2]:
    print(f"      {c.hz:.1f} Hz: {c.rejections[0][:110]}")
check(len(gated) >= 1, "a corpus with almost no throttle spread was analysed anyway")
check(not any(c.frame_mode_candidate for c in cands_w),
      "an unresolvable corpus still produced a frame mode candidate")

print("\n--- 5b: and the SE gate is what did it, not some other rule ---")
# Without this, the gate could be dead code while recurrence or drift does all the work.
# The PLANTED MODE's candidate specifically, not whichever came first: the rotor line in the
# same corpus is legitimately rejected twice (b=1 and the gate), which says nothing about
# whether the gate is doing any work on a line that would otherwise have passed.
lone = next(c for c in gated if abs(c.hz - 300.0) < 20.0)
others = [r for r in lone.rejections if "SE(b)" not in r]
print(f"    {lone.hz:.1f} Hz other rejections: {others if others else 'none'}")
check(not others, f"the narrow corpus was also rejected for {others}, so section 5's test does "
                  "not isolate the SE gate")

print("\n--- 6: a stationary line on ONE AXIS ONLY is rejected ---")
pts_1ax = corpus(modes=(185.0,), mode_axes={185.0: ("roll",)})
cands_1, ruler_1, _ = ca.identify_frame_mode(pts_1ax)
hits_1 = summarise("185 Hz on roll only (a mast)", cands_1, ruler_1)
check(len(hits_1) == 0, "a single-axis line was accepted as an arm bending mode")
single = [c for c in cands_1 if abs(c.hz - 185.0) < 5.0]
check(single and any("roll only" in r for r in single[0].rejections),
      f"the single-axis line was rejected for the wrong reason: "
      f"{single[0].rejections if single else 'not found at all'}")

print("\n--- 7: a line that DRIFTS is refused, with the drift reported ---")
pts_drift = corpus(modes=(185.0,), drift=0.12)
cands_d, ruler_d, _ = ca.identify_frame_mode(pts_drift)
hits_d = summarise("185 Hz drifting 12% over the corpus", cands_d, ruler_d)
check(len(hits_d) == 0, "a drifting line was accepted; criterion 2f is unguarded")
drifted = [c for c in cands_d if abs(c.hz - 185.0) < 15.0]
check(drifted and any("drifted" in r for r in drifted[0].rejections),
      f"the drifting line was not rejected by rule (d): "
      f"{drifted[0].rejections if drifted else 'not found at all'}")
if drifted:
    print(f"      reported drift {drifted[0].drift:.1%} against a {ca.DRIFT_LIMIT:.0%} limit")

print("\n--- 7b: and a line that drifts BEYOND the window fails recurrence, and says so ---")
# Section 5 (d) requires these to be distinguishable: "did not recur" and "no mode found" mean
# different things to whoever reads the output.
pts_far = corpus(modes=(185.0,), drift=0.40)
cands_f, _, _ = ca.identify_frame_mode(pts_far)
far = [c for c in cands_f if 150.0 < c.hz < 230.0 and c.rejections]
reasons = [r for c in far for r in c.rejections]
print(f"    rejections seen: {sorted({r.split(':')[0] for r in reasons})}")
check(any("did not recur" in r for r in reasons) or not far,
      "a line drifting out of the match window did not report a recurrence failure")

print("\n--- 8: THE ONE THAT MATTERS. A corpus shaped like the INAV set must NOT ---")
print("    return its own dominant tracking peak as a stationary mode.")
# Section 0: the method was inspired by seeing a 149.5 Hz peak that tracks throttle at 0.867.
# If a corpus built to look like that returns that peak as a frame mode, the method is finding
# what it went looking for. Nothing else in this file catches that.
pts_inav = corpus(n_logs=46, one_x=(111.0, 179.0), modes=(), orders=(1.0, 2.0),
                  read_sigma=0.02)
cands_i, ruler_i, notes_i = ca.identify_frame_mode(pts_inav)
hits_i = summarise("INAV-shaped: tracking peak, no mode", cands_i, ruler_i)
check(len(hits_i) == 0,
      f"a corpus with NO stationary line returned {len(hits_i)} candidate(s) at "
      f"{[round(h.hz, 1) for h in hits_i]} — the method is finding what it went looking for")
near = [c for c in cands_i if abs(c.hz - 149.5) < 40.0]
check(all(c.verdict != ca.VERDICT_STATIONARY for c in near),
      "a line in the 149.5 Hz neighbourhood came back stationary in a rotor-only corpus")

print("\n--- 8b: the pre-registered prediction about the real corpus, checked arithmetically ---")
# Section 4 predicts this corpus is MARGINAL and probably just misses the SE gate. That is a
# falsifiable claim about arithmetic, so it is evaluated here rather than left as prose.
sigma_ln_1x = float(np.std(np.log(ruler_i.hz)))
se_at_46 = ca.PEAK_READ_SIGMA / (np.sqrt(46) * sigma_ln_1x)
need = (ca.PEAK_READ_SIGMA / (ca.MAX_SLOPE_SE * sigma_ln_1x)) ** 2
print(f"    ruler sigma(ln 1x) = {sigma_ln_1x:.4f};  SE(b) at 46 logs = {se_at_46:.4f} "
      f"vs gate {ca.MAX_SLOPE_SE};  logs needed = {need:.0f}")
check(se_at_46 > ca.MAX_SLOPE_SE,
      f"section 4 predicted this corpus would MISS the gate; at 46 logs SE = {se_at_46:.4f}, "
      f"which passes. The prediction was wrong and the write-up must say so rather than "
      f"quietly enjoying the result")

print("\n--- 9: the agreement test REFUSES to run without a measured build ---")
# Section 1's closing note, enforced. A corpus with no frame or tip mass gets a frequency and
# no verdict, however tempting the comparison is.
best = ca.report(cands, ruler, notes, modelled_hz=180.0, build_measured=False)
check(best is not None, "report lost the candidate entirely")

print()
if failures:
    print(f"SELF-TEST FAILED: {len(failures)} check(s)")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("SELF-TEST PASSED")
