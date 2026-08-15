"""Check on the INAV reader (tools/inav_log.py).

Two halves, and the split is deliberate:

  * SYNTHETIC. The unit and pre-filter verifications are pure numpy and are exercised on arrays
    built here, including the cases that must be REFUSED. These run everywhere, with no log
    files and without orangebox, and they are what proves the checks can fail.
  * REAL. The 141 INAV logs in ~/Downloads/logs are the fixture set, and they are unusually
    good at it because a fifth of them are broken. They are NOT vendored — validation.md's
    cite-don't-vendor rule, the same treatment Oscar's CSV got — so every section that needs
    them SKIPS LOUDLY when they are absent. Of the two options that rule leaves for an in-tree
    fixture, a decimated excerpt or a fetch script, NEITHER is taken: these are one person's
    personal flight logs from a private SD card, so there is nothing to fetch and an excerpt
    would be publishing them. The skip is the honest option here.

The named files below were chosen because each is a DIFFERENT failure, and the names are
recorded so the survey stays reproducible:

    LOG00262  loads; gyroRaw measurably pre-filter at 22.5x
    LOG00277  truncated (697 I/P frames)
    LOG00322  corrupt frame stream: struct 'I' format requires 0 <= number <= 4294967295
    LOG00275  undecodable: InvalidHeaderException at 0xC06

Run: .venv/bin/python tools/inav_log_selftest.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import impact_analysis as ia  # noqa: E402
import inav_log  # noqa: E402
import resonance_analysis as ra  # noqa: E402

LOGS = os.path.expanduser("~/Downloads/logs")
CLEAN = os.path.join(LOGS, "LOG00262.TXT")
TRUNCATED = os.path.join(LOGS, "LOG00277.TXT")
CORRUPT_FRAMES = os.path.join(LOGS, "LOG00322.TXT")
UNDECODABLE = os.path.join(LOGS, "LOG00275.TXT")

failures, skipped = [], []


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


def have(path, what):
    if os.path.exists(path):
        return True
    skipped.append(f"{what}: {path} not present (cite-don't-vendor; see docstring)")
    print(f"    SKIPPED: {os.path.basename(path)} not found")
    return False


# ---------------------------------------------------------------------------
# Synthetic: the two verifications, and proof that each can refuse
# ---------------------------------------------------------------------------

FS = 982.0
RNG = np.random.default_rng(4)
N = 20000


def synth(deg_s_slope=1.0, raw_is_filtered=False, same_axis=False):
    """Columns shaped like a decoded INAV log, in the reduced layout read_inav builds."""
    t = np.arange(N) * (1e6 / FS)
    # A rate demand the airframe follows, plus vibration the demand does not contain.
    rate = np.cumsum(RNG.standard_normal(N)) * 0.5
    rate -= rate.mean()
    vib = np.sin(2 * np.pi * 150.0 * np.arange(N) / FS) * 8.0
    raw0 = rate * deg_s_slope + vib + 0.5 * RNG.standard_normal(N)
    adc0 = rate * deg_s_slope + 0.5 * RNG.standard_normal(N)  # lowpass killed the 150 Hz line
    rate1 = np.cumsum(RNG.standard_normal(N)) * 0.5
    rate1 -= rate1.mean()
    raw1 = rate1 * deg_s_slope + np.sin(2 * np.pi * 210.0 * np.arange(N) / FS) * 8.0
    adc1 = rate1 * deg_s_slope
    if raw_is_filtered:
        raw1 = adc1.copy()
    if same_axis:
        raw1, adc1, rate1 = raw0.copy(), adc0.copy(), rate.copy()
    cols = {
        "time": t,
        # Yaw mirrors pitch here. It is never analysed by this module and only has to be a
        # well-scaled deg/s channel so the unit check sees three consistent axes rather than
        # one deliberately-wrong one it would then correctly refuse.
        "gyroADC[0]": adc0, "gyroADC[1]": adc1, "gyroADC[2]": adc1,
        "gyroRaw[0]": raw0, "gyroRaw[1]": raw1, "gyroRaw[2]": raw1,
        "motor[0]": np.full(N, 1270.0),
        "axisRate[0]": rate, "axisRate[1]": rate1, "axisRate[2]": rate1,
    }
    col = {n: i for i, n in enumerate(cols)}
    return np.column_stack(list(cols.values())), col


print("--- 1: gyro units are PROVEN deg/s against axisRate, not assumed ---")
data, col = synth()
ev = inav_log._verify_deg_s(data, col, "synthetic")
print(f"    {ev}")
check("slope" in ev and "roll" in ev, f"the deg/s verdict does not report what it measured: {ev}")

print("\n--- 1b: and a raw-sensor-count channel is REFUSED, not silently scaled ---")
# The failure this check exists for: gyro logged in sensor counts, ~16x deg/s here. Every
# frequency the analysis reported would be right, but every amplitude and the unit label wrong
# — and on a different board the factor lands where it changes the answer.
data_bad, col_bad = synth(deg_s_slope=16.0)
got, msg = refuses(inav_log._verify_deg_s, data_bad, col_bad, "synthetic")
check(got, "a 16x scale factor on the gyro columns was accepted as deg/s")
if got:
    print("   ", msg.split(":", 1)[1].strip()[:150])

print("\n--- 1c: a log that never moved is REPORTED unverified, not refused ---")
# A bench tap has no rate command at all, so a hard refusal here would refuse the one input
# this reader exists to serve. Frequency and damping are scale-invariant; amplitude is not.
data_still, col_still = synth()
for i in range(3):
    data_still[:, col_still[f"axisRate[{i}]"]] = 0.0
ev_still = inav_log._verify_deg_s(data_still, col_still, "synthetic")
print(f"    {ev_still[:120]}")
check("NOT VERIFIED" in ev_still, f"a still log did not report an unverified scale: {ev_still}")
check("scale-invariant" in ev_still,
      "the unverified verdict does not say what it does and does not invalidate")

print("\n--- 2: gyroRaw is confirmed pre-filter BY MEASUREMENT, not by its name ---")
unf, ev = inav_log._verify_gyro_raw(data, col, "", "synthetic")
print(f"    {ev}")
check(unf, f"a genuinely pre-filter gyroRaw was not recognised: {ev}")
check("x (roll)" in ev, "the accepted evidence does not carry the measured ratio")

print("\n--- 2b: a gyroRaw that is really a copy of gyroADC is REFUSED ---")
# The whole point of not trusting the field name. A firmware where gyroRaw is post-filter, or
# a board where it means something else, produces exactly this.
data_f, col_f = synth(raw_is_filtered=True)
unf_f, ev_f = inav_log._verify_gyro_raw(data_f, col_f, "", "synthetic")
print(f"    {ev_f}")
check(not unf_f, "a post-filter gyroRaw[1] was accepted as pre-filter")

print("\n--- 2c: and two gyroRaw columns that are the SAME AXIS are refused ---")
data_s, col_s = synth(same_axis=True)
unf_s, ev_s = inav_log._verify_gyro_raw(data_s, col_s, "", "synthetic")
print(f"    {ev_s}")
check(not unf_s, "a same-axis gyroRaw[0..1] pair was accepted as roll and pitch")
check("SAME AXIS" in ev_s, f"refused for the wrong reason: {ev_s}")

print("\n--- 3: THE CHECK THAT THE CHECKS CAN FAIL ---")
print("    Each refusal above needs its own check; here is what the OTHER one says.")
# 2b must be caught by the pre-filter test and NOT by the axis test, and vice versa for 2c.
# Without this, one check could be doing all the work and the other could be dead code.
same_in_2b, r_2b = ra._same_axis(data_f[:, col_f["gyroRaw[0]"]], data_f[:, col_f["gyroRaw[1]"]])
print(f"    2b's fixture: axis test says same={same_in_2b} (r={r_2b:.3f}) — so the pre-filter "
      "test is what rejected it")
check(not same_in_2b, "2b is rejected by the axis test too, so it does not exercise the "
                      "pre-filter half of _verify_gyro_raw")
pre_ok, _ = ra._looks_prefilter(data_s[:, col_s["gyroRaw[0]"]],
                                data_s[:, col_s["gyroADC[0]"]], FS)
print(f"    2c's fixture: pre-filter test says unfiltered={pre_ok} — so the axis test is what "
      "rejected it")
check(pre_ok, "2c is rejected by the pre-filter test too, so it does not exercise the axis half")

# ---------------------------------------------------------------------------
# Real files
# ---------------------------------------------------------------------------

print("\n--- 4: a real INAV log loads, and every verdict is measured ---")
log = None
if have(CLEAN, "clean-log sections"):
    log = inav_log.read_inav(CLEAN)
    for line in (log.gyro_evidence, log.units_evidence, log.sampling_evidence):
        print(f"    {line}")
    check(log.unfiltered, "LOG00262's gyroRaw was not recognised as pre-filter")
    check("22" in log.gyro_evidence.split("x (roll)")[0][-5:],
          f"the measured roll ratio moved from the 22.5x recorded in the docstring: "
          f"{log.gyro_evidence}")
    # The guard from 28d23ee has to be ON this path, not merely importable by it.
    check("uniform sampling" in log.sampling_evidence,
          "check_uniform_sampling's verdict never reached sampling_evidence")
    check("preamble" in log.sampling_evidence,
          "the preamble skip is not disclosed in the evidence, so the log was quietly shortened")

print("\n--- 5: the three shapes of broken file, each refused with its own reason ---")
for path, what, needle in (
    (TRUNCATED, "truncated", "truncated or empty"),
    (CORRUPT_FRAMES, "corrupt frame stream", "corrupt frame stream"),
    (UNDECODABLE, "undecodable header", "undecodable"),
):
    if not have(path, f"{what} section"):
        continue
    got, msg = refuses(inav_log.read_inav, path)
    check(got, f"{os.path.basename(path)} ({what}) did not raise ValueError")
    if got:
        print(f"    {msg.splitlines()[0][:160]}")
        check(needle in msg, f"{os.path.basename(path)} refused for the wrong reason: {msg[:120]}")

print("\n--- 6: load_inav REFUSES a flight log for want of rpm, and says PWM ---")
if log is not None:
    got, msg = refuses(inav_log.load_inav, CLEAN, arm_m=0.110, tip_mass_kg=0.0365, blades=3)
    check(got, "load_inav returned a Trace for an INAV flight log")
    if got:
        print("   ", msg.splitlines()[1].strip())
        check("PWM" in msg, "the refusal does not name PWM as the reason")
        # LTHL-18 already recorded one wrong diagnosis of this exact shape — telling a pilot to
        # enable bidirectional DShot on a log that already had it. The same mistake here would
        # be telling a pilot with PWM ESCs to enable something their hardware cannot do.
        check("bidirectional DShot" not in msg or "HARDWARE" in msg,
              "the refusal blames a setting; on PWM ESCs there is no setting to change")
        check("escRPM" in msg, "the refusal does not warn off escRPM, which looks like rpm")
        check(log.gyro_evidence.split(" — ")[0] in msg,
              "the refusal drops the evidence that WAS measured; a refusal with no evidence "
              "cannot be audited")

print("\n--- 7: load_inav_impact returns a Recording that impact_analysis accepts ---")
if log is not None:
    rec = inav_log.load_inav_impact(CLEAN, arm="A")
    print(f"    source={rec.source} fs={rec.sample_rate_hz:.1f} Hz  n={len(rec.signal)}")
    check(rec.source == "inav", f"Recording.source is {rec.source!r}, not 'inav'")
    check(rec.unfiltered, "the Recording is marked filtered despite gyroRaw passing")
    check(rec.sampling_evidence == log.sampling_evidence,
          "sampling_evidence did not reach the Recording")
    check(abs(rec.sample_rate_hz - 982.0) < 5.0,
          f"sample rate {rec.sample_rate_hz:.1f} Hz is not the ~982 Hz this set logs at")
    check("gyroRaw" in rec.unfiltered_evidence,
          "the Recording does not say which column it took")
    # assert_usable calls sys.exit on a filtered recording; this one must survive it.
    ia.assert_usable(rec)
    print("    impact_analysis.assert_usable accepted it")

print("\n--- 8: a Recording from an INAV log carries NO build ---")
if log is not None:
    rec = inav_log.load_inav_impact(CLEAN, arm="A")
    banned = ("arm_m", "tip_mass_kg", "blades", "frame", "prop")
    leaked = [k for k in rec.header if k.lower() in banned]
    check(not leaked, f"build properties leaked out of the log header: {leaked}")
    check(not hasattr(rec, "build"), "Recording grew a build attribute")
    check(rec.header.get("Craft name", "") == "",
          "Craft name is non-empty on this set; the no-inference rule now has something to "
          "be tempted by and needs re-reading")

print()
for s in skipped:
    print(f"SKIPPED: {s}")
if failures:
    print(f"SELF-TEST FAILED: {len(failures)} check(s)")
    for f in failures:
        print(f"  - {f}")
    sys.exit(1)
print("SELF-TEST PASSED" + (" (with skips)" if skipped else ""))
