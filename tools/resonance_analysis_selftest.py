"""Synthetic check on the ORDER-TRACKING statistic.

Not evidence about the model. Evidence about the ANALYSIS: a trace with a resonance planted
at a known frequency, and the rule must return the planted frequency. Plus two controls that
must NOT come back looking like a confident detection.
"""
import sys, numpy as np
sys.path.insert(0, "/Users/ritwiksingh/Desktop/OneWeekendAI/lothal/tools")
import resonance_analysis as ra

fs = 1000.0
T = 30.0
t = np.arange(0, T, 1 / fs)
rng = np.random.default_rng(0)


def make(planted, zeta=0.03, rot_lo=40, rot_hi=200, noise=0.5):
    f1 = rot_lo + (rot_hi - rot_lo) * (t / T)
    ph = 2 * np.pi * np.cumsum(f1) / fs
    if planted is None:
        g = lambda f: np.ones_like(f)
    else:
        def g(f):
            r = f / planted
            return 1.0 / np.sqrt((1 - r ** 2) ** 2 + (2 * zeta * r) ** 2)
    # forcing grows as omega^2 (imbalance), which the trend removal must survive
    x = np.zeros_like(t)
    for k, amp in ((1, 1.0), (2, 0.5), (3, 0.8)):
        x += amp * (f1 / rot_lo) ** 2 * g(k * f1) * np.sin(k * ph)
    x += noise * rng.standard_normal(len(t))
    return x, f1


def run(label, planted, **kw):
    x, f1 = make(planted, **kw)
    tr = ra.Trace(name=label, source="synthetic", sample_rate_hz=fs,
                  roll_deg_s=x, pitch_deg_s=x, rot_hz=f1, blades=3,
                  unfiltered=True, unfiltered_evidence="synthetic")
    modelled = planted if planted else 180.0
    r = ra.analyse(tr, "roll", modelled)
    err = "" if planted is None else f"  err {(r.peak.hz - planted) / planted:+.1%}"
    print(f"{label:28s} planted={planted}  found {r.peak.hz:6.1f} Hz "
          f"({r.peak.prominence:.2f}x) covered={r.covered} ambiguous={r.ambiguous}{err}")
    print(f"{'':28s} runners-up: {[(round(p.hz,1), round(p.prominence,2)) for p in r.runners_up]}")
    return r


print("--- detections: the rule must recover the planted mode ---")
for p in (143.0, 180.0, 260.0, 420.0):
    r = run(f"planted {p:.0f} Hz", p)
    assert (not r.covered) or abs(r.peak.hz - p) / p < 0.06, "ANALYSIS FAILED"

print("\n--- controls: nothing planted, and a sweep that misses the model ---")
run("no resonance at all", None)
run("sweep stops below model", None, rot_lo=25, rot_hi=45)

print("\n--- the check that the check can fail: perturbed anchor ---")
x, f1 = make(143.0)
tr = ra.Trace(name="perturb", source="synthetic", sample_rate_hz=fs, roll_deg_s=x,
              pitch_deg_s=x, rot_hz=f1, blades=3, unfiltered=True, unfiltered_evidence="synthetic")
r = ra.analyse(tr, "roll", 143.0)
for model_hz in (143.0, 180.0, 250.0):
    e = (r.peak.hz - model_hz) / model_hz
    print(f"  measured {r.peak.hz:.1f} Hz vs a model saying {model_hz:.0f} Hz -> "
          f"{e:+.1%} {'PASS' if abs(e) <= ra.AGREEMENT_FRACTION else 'FAIL'}")
