"""Synthetic check on the IMPACT analyser (LTHL-49).

Not evidence about the model. Evidence about the ANALYSIS, and specifically that it can be
WRONG — a tool that always returns a number is not measuring anything. Four things are proved
here, and the last one is the one that matters:

  1. planted FREQUENCIES are recovered inside the tolerance the bound assumes;
  2. planted DAMPING is recovered — new here, and the frequency test does not cover it, since
     an estimator can get f right from the phase slope while getting the envelope wrong;
  3. controls with no mode return NOT FOUND, both a pure-noise trace and a NON-DECAYING tone
     (a mains hum makes a beautiful spectral peak and is not a mode);
  4. MOVING THE PLANTED MODE MOVES THE ANSWER. LTHL-18's version of this caught that a
     synthetic-sweep validation was a closed loop that could not have disagreed. Same trap,
     same guard: the tool has to track the truth, not echo the model it is handed.

Run: .venv/bin/python tools/impact_analysis_selftest.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import impact_analysis as ia

FS = 4000.0
RNG = np.random.default_rng(7)

#: The self-test's own tolerance, tighter than the measurement bound on purpose: the bound is
#: about the PHYSICS being uncertain, this is about the ARITHMETIC being right. If the analyser
#: cannot recover a synthetic mode to 1% then the +-1.5% peak-picking term in section 1 of the
#: pre-registration is a lie.
FREQ_TOLERANCE = 0.01
#: Damping is a harder estimate than frequency and the bound it feeds is a factor of two, so
#: 15% here is comfortably strict enough to catch a broken estimator.
ZETA_TOLERANCE = 0.15


def ringdown(modes, strikes=5, seconds=None, noise=0.02, decaying=True):
    """A trace of `strikes` taps, each exciting every mode in `modes` = [(hz, zeta, amp)]."""
    gap = 0.6
    seconds = seconds or (strikes * gap + 0.5)
    t = np.arange(0, seconds, 1.0 / FS)
    x = noise * RNG.standard_normal(len(t))
    for s in range(strikes):
        t0 = 0.15 + s * gap
        i0 = int(t0 * FS)
        rel = t[i0:] - t0
        for hz, zeta, amp in modes:
            phase = RNG.uniform(0, 2 * np.pi)  # taps are not phase-coherent, and must not be
            env = np.exp(-zeta * 2 * np.pi * hz * rel) if decaying else np.ones_like(rel)
            x[i0:] += amp * env * np.sin(2 * np.pi * hz * rel + phase)
    return x


def rec(x, **meta):
    return ia.Recording(name=meta.pop("name", "synthetic"), source="synthetic",
                        sample_rate_hz=FS, signal=x, **meta)


def show(label, groups, strikes):
    print(f"{label:34s} {strikes} strikes, {len(groups)} recurring modes")
    for g in groups:
        print(f"{'':34s}   {g.hz:7.2f} Hz  zeta {g.zeta:.4f}  prom {g.prominence:4.1f}x  "
              f"{g.strikes}/{g.of_strikes} strikes  R-spread {g.hz_spread:.2f} Hz")


failures = []


def check(condition, message):
    if not condition:
        failures.append(message)
        print(f"    *** FAILED: {message}")


print("--- 1 & 2: planted modes, frequency AND damping ---")
for f_hz, zeta in ((143.0, 0.03), (180.0, 0.03), (260.0, 0.015), (420.0, 0.05)):
    x = ringdown([(f_hz, zeta, 1.0)])
    groups, strikes = ia.analyse(rec(x))
    show(f"planted {f_hz:.0f} Hz zeta {zeta:.3f}", groups, strikes)
    hit = next((g for g in groups if abs(g.hz - f_hz) <= 0.06 * f_hz), None)
    check(hit is not None, f"{f_hz} Hz mode not found at all")
    if hit:
        check(abs(hit.hz - f_hz) / f_hz <= FREQ_TOLERANCE,
              f"{f_hz} Hz recovered as {hit.hz:.2f} Hz, outside {FREQ_TOLERANCE:.0%}")
        check(abs(hit.zeta - zeta) / zeta <= ZETA_TOLERANCE,
              f"zeta {zeta} recovered as {hit.zeta:.4f}, outside {ZETA_TOLERANCE:.0%}")

print("\n--- 1b: two modes at once, which is what a real tap gives ---")
x = ringdown([(165.0, 0.03, 1.0), (390.0, 0.02, 0.6)])
groups, strikes = ia.analyse(rec(x))
show("planted 165 + 390 Hz", groups, strikes)
for want in (165.0, 390.0):
    hit = next((g for g in groups if abs(g.hz - want) <= 0.06 * want), None)
    check(hit is not None and abs(hit.hz - want) / want <= FREQ_TOLERANCE,
          f"two-mode trace lost or mis-measured {want} Hz")

print("\n--- 3: controls. These must NOT return a mode ---")
groups, strikes = ia.analyse(rec(0.05 * RNG.standard_normal(int(4.0 * FS))))
show("noise only, no strikes", groups, strikes)
check(len(groups) == 0, f"noise-only trace returned {len(groups)} modes")

x = ringdown([(200.0, 0.03, 1.0)], decaying=False)
groups, strikes = ia.analyse(rec(x))
show("200 Hz tone that never decays", groups, strikes)
check(not any(abs(g.hz - 200.0) <= 0.06 * 200.0 for g in groups),
      "a non-decaying tone was reported as a mode; the R^2 gate is not working")

print("\n--- 4: the check that the check can fail. Move the mode, the answer must move. ---")
measured = []
for planted in (143.0, 180.0, 230.0):
    groups, _ = ia.analyse(rec(ringdown([(planted, 0.03, 1.0)])))
    ident = ia.identify_first_bending({"A": groups, "B": groups})
    measured.append((planted, ident.hz))
    print(f"    planted {planted:6.1f} Hz -> identified {ident.hz if ident.hz else float('nan'):6.1f} Hz")
check(all(m is not None for _, m in measured), "identification returned nothing on a planted mode")
if all(m is not None for _, m in measured):
    spread = max(m for _, m in measured) - min(m for _, m in measured)
    check(spread > 50.0, f"the answer barely moved ({spread:.1f} Hz) when the truth moved 87 Hz "
                         "— the tool is echoing, not measuring")

print("\n--- 4b: and the same trace against three different models ---")
groups, _ = ia.analyse(rec(ringdown([(143.0, 0.03, 1.0)])))
ident = ia.identify_first_bending({"A": groups, "B": groups})
for model_hz in (143.0, 180.0, 250.0):
    e = (ident.hz - model_hz) / model_hz
    verdict = "PASS" if abs(e) <= ia.IMPACT_AGREEMENT_FRACTION else "FAIL"
    print(f"    measured {ident.hz:.1f} Hz vs a model saying {model_hz:.0f} Hz -> {e:+.1%} {verdict}")
check(abs((ident.hz - 250.0) / 250.0) > ia.IMPACT_AGREEMENT_FRACTION,
      "a 143 Hz measurement did not fail a 250 Hz model; the bound cannot reject anything")

print("\n--- 5: the mode-identification rule rejects what it is supposed to reject ---")
# A room resonance: same frequency on every arm, unmoved by taking the prop off.
arm_groups, _ = ia.analyse(rec(ringdown([(120.0, 0.02, 0.9), (185.0, 0.03, 1.0)])))
shift = ia.expected_props_off_shift(0.0365, 0.0045)
# With the prop off, the ARM mode moves by sqrt(36.5/32) and the room mode does not.
off_groups, _ = ia.analyse(rec(ringdown([(120.0, 0.02, 0.9), (185.0 * shift, 0.03, 1.0)])))
show(f"props on  (120 room + 185 arm)", arm_groups, 5)
show(f"props off (120 room + {185.0*shift:.1f} arm)", off_groups, 5)
ident = ia.identify_first_bending({"A": arm_groups, "B": arm_groups},
                                  props_off=off_groups, expected_shift=shift)
print(f"    expected shift x{shift:.3f}; identified {ident.hz} Hz")
for hz, why in ident.rejected:
    print(f"    rejected {hz:.1f} Hz: {why}")
check(ident.hz is not None and abs(ident.hz - 185.0) < 0.06 * 185.0,
      f"criterion (c) did not reject the 120 Hz room mode (identified {ident.hz})")

print("\n--- 5b: and returns NO MODE IDENTIFIED when nothing qualifies ---")
ident = ia.identify_first_bending({"A": arm_groups, "B": arm_groups},
                                  props_off=[], expected_shift=shift)
print(f"    identified: {ident.hz}  reason: {ident.reasons[0]}")
check(ident.hz is None, "a candidate was identified with no props-off evidence at all")

print()
if failures:
    print(f"SELF-TEST FAILED: {len(failures)} check(s)")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("SELF-TEST PASSED")
