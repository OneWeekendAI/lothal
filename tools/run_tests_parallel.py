#!/usr/bin/env python3
"""Helper for tools/run_tests_parallel.sh: `pack` and `summary`. Pure bookkeeping, no process control."""
import os, re, sys


def suites(rt):
    src = open(rt).read()
    block = src.split("const SUITES := [", 1)[1].split("\n\nfunc ", 1)[0]
    block = block[: block.rindex("]")]
    seen, out = set(), []
    for s in re.findall(r'"([^"]+)"', block):
        if s not in seen:  # SUITES lists "prop capability" twice; run it once
            seen.add(s)
            out.append(s)
    return out


def load_timings(path):
    t = {}
    if os.path.exists(path):
        for line in open(path):
            if "\t" in line:
                k, v = line.rstrip("\n").rsplit("\t", 1)
                try:
                    t[k] = float(v)
                except ValueError:
                    pass
    return t


# Suites that assert on wall-clock time (a per-tick budget, a real-time audio budget, a timing ratio).
# Under N-way CPU contention they fail for reasons that say nothing about the code, so they are kept out
# of the shards and run SERIALLY after every shard has finished, as shard number JOBS, alone on the
# machine. They still count toward the exit code. Add a suite here when it asserts on elapsed time.
SERIAL = ["sim perf", "rotor synth", "studio"]


# Test classes that are NOT suites: helpers and harnesses run by something else. Every other
# tests/**/test_*.gd must be named by one of the two runners, or `pack` refuses to start: a test file
# no runner references is never compiled, so a parse error in it (or the whole file) goes missing
# silently and the run still says PASS.
NOT_SUITES = {"TestResult", "TestSimReality", "TestBfMechanisms"}
RUNNERS = ["tests/run_tests.gd", "tests/sim_reality/run_suites.gd"]


def unwired(root):
    import glob
    text = "".join(open(os.path.join(root, r)).read() for r in RUNNERS)
    bad = []
    for f in sorted(glob.glob(os.path.join(root, "tests", "**", "test_*.gd"), recursive=True)):
        m = re.search(r"^class_name (\w+)", open(f, errors="replace").read(), re.M)
        rel = os.path.relpath(f, root)
        if not m:
            bad.append("%s (no class_name)" % rel)
        elif m.group(1) not in NOT_SUITES and not re.search(r"\b%s\b" % m.group(1), text):
            bad.append("%s (%s is in no runner)" % (rel, m.group(1)))
    return bad


def pack(rt, timings, jobs, outdir):
    bad = unwired(os.path.dirname(os.path.dirname(os.path.abspath(rt))))
    if bad:
        print("[parallel] REFUSING TO RUN: test files no runner calls (their checks would go missing):")
        for b in bad:
            print("  " + b)
        print("\nRESULT: FAIL")
        sys.exit(2)
    items = suites(rt) + ["@tail", "@sr"]
    only = os.environ.get("ONLY")  # ONLY="a|b": just those suites, no tail/SR (for trying the runner out)
    if only:
        items = [i for i in items if i in only.split("|")]
    serial = [i for i in items if i in SERIAL]
    items = [i for i in items if i not in SERIAL]
    t = load_timings(timings)
    known = sorted(v for k, v in t.items() if k in items)
    default = known[len(known) // 2] if known else 10.0
    cost = {i: t.get(i, default) for i in items}
    shards = [[] for _ in range(jobs)]
    load = [0.0] * jobs
    for i in sorted(items, key=lambda x: -cost[x]):  # greedy longest-first
        k = load.index(min(load))
        shards[k].append(i)
        load[k] += cost[i]
    for k, sh in enumerate(shards):
        with open(os.path.join(outdir, "shard_%d.txt" % k), "w") as f:
            f.write("\n".join(sh) + "\n")
    if serial:  # shard JOBS: run by the shell after all the others have exited
        with open(os.path.join(outdir, "shard_%d.txt" % jobs), "w") as f:
            f.write("\n".join(serial) + "\n")
    print("serial after the shards: %s" % (", ".join(serial) or "none"))
    print("packed %d items into %d shards; estimated shard seconds: %s (%d items without a timing used %.1fs)" % (
        len(items), jobs, ", ".join("%.0f" % l for l in load), len([i for i in items if i not in t]), default))


# Godot reports a script that failed to parse or compile with these; any one of them in a worker log
# means some code (and maybe some checks) never ran, so it fails the run naming the file.
SCRIPT_ERR = re.compile(r"(Parse Error|Compile Error|Failed to load script|Could not resolve class|Could not find type|Failed to compile)")
SCRIPT_AT = re.compile(r"(res://[^\s:)]+\.gd)")


def class_file(cls):
    import glob
    for f in glob.glob("**/*.gd", recursive=True):
        if ".claude" in f or f.startswith(".godot"):
            continue
        try:
            if re.search(r"^class_name %s\b" % cls, open(f, errors="replace").read(), re.M):
                return f
        except OSError:
            pass
    return "?"


def load_counts(path):
    c = {}
    if os.path.exists(path):
        for line in open(path):
            if "\t" in line:
                k, v = line.rstrip("\n").rsplit("\t", 1)
                if v.isdigit():
                    c[k] = int(v)
    return c


def summary(outdir, timings, wall, jobs, statuses):
    passed = failed = 0
    fails, times, problems = [], {}, []
    counts = {}  # suite -> checks it reported this run
    script_errs = []
    for k in range(jobs):
        log = os.path.join(outdir, "worker_%d.log" % k)
        if not os.path.exists(log):
            continue
        started, done = None, set()
        saw_end = saw_sr_total = False
        cur = None  # suite whose results are being printed; "@tail" after the last listed suite
        pending_err = None
        for line in open(log, errors="replace"):
            line = line.rstrip("\n")
            if pending_err is not None:
                fm = SCRIPT_AT.search(line)
                script_errs.append("w%d %s -> %s" % (k, pending_err, fm.group(1) if fm else "?"))
                pending_err = None
            if SCRIPT_ERR.search(line):
                fm = SCRIPT_AT.search(line)
                if fm:
                    script_errs.append("w%d %s" % (k, line.strip()[:200]))
                else:
                    pending_err = line.strip()[:200]  # the file is named on the next " at:" line
            m = re.match(r"\[start\] (.*)", line)
            if m:
                started = m.group(1)
                cur = None
            m = re.match(r"\[suite\] (.*)", line)
            if m:
                cur = m.group(1)
                counts.setdefault(cur, 0)
            if line.startswith("[PASS]") or line.startswith("[FAIL]"):
                key = cur or "@tail"
                counts[key] = counts.get(key, 0) + 1
            m = re.match(r"(\S.*?)\s+(\d+) checks  ", line)  # sim_reality runner's per-suite line
            if m:
                counts["sr:" + m.group(1)] = int(m.group(2))
            m = re.match(r"\[time\] (.*) \| ([0-9.]+)$", line)
            if m:
                times[m.group(1)] = float(m.group(2))
                done.add(m.group(1))
            if line.startswith("[PASS]"):
                passed += 1
            elif line.startswith("[FAIL]"):
                failed += 1
                fails.append("w%d %s" % (k, line))
            elif re.match(r"\s+\[FAIL\] ", line):  # sim_reality runner's per-check failure line
                fails.append("w%d (sr) %s" % (k, line.strip()))
            m = re.match(r"TOTAL (\d+) checks, (\d+) failed", line)
            if m:
                n, f = int(m.group(1)), int(m.group(2))
                passed += n - f
                failed += f
                saw_sr_total = True
                if n == 0:
                    problems.append("worker %d: SR run produced no results" % k)
            if line.startswith("[runner] run_tests.gd reached the end"):
                saw_end = True
        if pending_err is not None:
            script_errs.append("w%d %s" % (k, pending_err))
        shard = open(os.path.join(outdir, "shard_%d.txt" % k)).read().split("\n")
        unfinished = "" if started is None or started in done else " (started, never finished)"
        if statuses[k] == 124:
            problems.append("worker %d TIMED OUT; last suite started: %s%s" % (k, started, unfinished))
        elif statuses[k] != 0:
            problems.append("worker %d exited %d; last suite started: %s%s" % (k, statuses[k], started, unfinished))
        if [s for s in shard if s and s != "@sr"] and not saw_end and statuses[k] != 124:
            problems.append("worker %d never reached the end of run_tests.gd (crash?); last suite started: %s%s" % (k, started, unfinished))
        if "@sr" in shard and not saw_sr_total and statuses[k] != 124:
            problems.append("worker %d: no SR TOTAL line (SR run crashed?)" % k)
        for s2 in shard:
            if s2 and not s2.startswith("@") and s2 not in done:
                problems.append("worker %d: suite \"%s\" was in its shard but never reported (missing)" % (k, s2))
    for e in script_errs:
        m = re.search(r'Could not resolve class "(\w+)"', e)
        if m:
            e += " [class %s is defined in %s]" % (m.group(1), class_file(m.group(1)))
        problems.append("script parse/compile error: %s" % e)
    old = load_timings(timings)
    old.update(times)
    with open(timings, "w") as f:
        for k2 in sorted(old):
            f.write("%s\t%.1f\n" % (k2, old[k2]))
    print("\n================ MERGED SUMMARY ================")
    print("PASS %d   FAIL %d   total %d   wall %ss   (%d workers)" % (passed, failed, passed + failed, wall, jobs))
    if fails:
        print("\nFailing lines:")
        for l in fails:
            print("  " + l[:300])
    print("\n10 slowest suites:")
    for k2, v in sorted(times.items(), key=lambda kv: -kv[1])[:10]:
        print("  %7.1fs  %s" % (v, k2))
    # Check-count ratchet. A full run (no ONLY) records how many checks each suite reported; the next
    # full run fails if the total dropped by more than CHECK_DROP_TOLERANCE, naming the suites that shrank.
    # Lowering the baseline on purpose (tests deleted): ALLOW_CHECK_DROP=1 for one run.
    countfile = os.environ.get("CHECK_COUNTS") or os.path.join(os.path.dirname(os.path.abspath(timings)), "suite_check_counts.tsv")
    full = not os.environ.get("ONLY")
    total = passed + failed
    prev = load_counts(countfile)
    tol = int(os.environ.get("CHECK_DROP_TOLERANCE", "5"))
    # A partial run (ONLY=) is held to the recorded counts of just the suites it ran, and never records.
    scope = None if full else [x for x in os.environ["ONLY"].split("|") if x in prev]
    base = prev.get("TOTAL") if full else (sum(prev[x] for x in scope) if scope else None)
    if base is not None:
        drop = base - total
        print("\nchecks: %d this run, %d recorded last full run (tolerance %d)" % (total, base, tol))
        if drop > tol and not os.environ.get("ALLOW_CHECK_DROP"):
            shrunk = ["%s %d->%d" % (s2, prev[s2], counts.get(s2, 0)) for s2 in sorted(prev)
                      if s2 != "TOTAL" and (full or s2 in scope) and counts.get(s2, 0) < prev[s2]]
            problems.append("check count fell by %d (%d -> %d), more than %d; suites that shrank: %s" % (
                drop, base, total, tol, ", ".join(shrunk) or "?"))
    bad = failed > 0 or bool(problems) or any(s != 0 for s in statuses)
    if full and not bad:
        with open(countfile, "w") as f:
            f.write("TOTAL\t%d\n" % total)
            for s2 in sorted(counts):
                f.write("%s\t%d\n" % (s2, counts[s2]))
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  " + p)
    print("\nRESULT: %s   (logs: %s)" % ("FAIL" if bad else "PASS", outdir))
    return 1 if bad else 0


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "pack":
        pack(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
    elif c == "summary":
        sys.exit(summary(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), [int(x) for x in sys.argv[6].split(",")]))
