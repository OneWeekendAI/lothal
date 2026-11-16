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


def pack(rt, timings, jobs, outdir):
    items = suites(rt) + ["@tail", "@sr"]
    only = os.environ.get("ONLY")  # ONLY="a|b": just those suites, no tail/SR (for trying the runner out)
    if only:
        items = [i for i in items if i in only.split("|")]
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
    print("packed %d items into %d shards; estimated shard seconds: %s (%d items without a timing used %.1fs)" % (
        len(items), jobs, ", ".join("%.0f" % l for l in load), len([i for i in items if i not in t]), default))


def summary(outdir, timings, wall, jobs, statuses):
    passed = failed = 0
    fails, times, problems = [], {}, []
    for k in range(jobs):
        log = os.path.join(outdir, "worker_%d.log" % k)
        if not os.path.exists(log):
            continue
        started, done = None, set()
        saw_end = saw_sr_total = False
        for line in open(log, errors="replace"):
            line = line.rstrip("\n")
            m = re.match(r"\[start\] (.*)", line)
            if m:
                started = m.group(1)
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
        shard = open(os.path.join(outdir, "shard_%d.txt" % k)).read().split()
        unfinished = "" if started is None or started in done else " (started, never finished)"
        if statuses[k] == 124:
            problems.append("worker %d TIMED OUT; last suite started: %s%s" % (k, started, unfinished))
        elif statuses[k] != 0:
            problems.append("worker %d exited %d; last suite started: %s%s" % (k, statuses[k], started, unfinished))
        if [s for s in shard if s != "@sr"] and not saw_end and statuses[k] != 124:
            problems.append("worker %d never reached the end of run_tests.gd (crash?); last suite started: %s%s" % (k, started, unfinished))
        if "@sr" in shard and not saw_sr_total and statuses[k] != 124:
            problems.append("worker %d: no SR TOTAL line (SR run crashed?)" % k)
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
    if problems:
        print("\nPROBLEMS:")
        for p in problems:
            print("  " + p)
    print("\n10 slowest suites:")
    for k2, v in sorted(times.items(), key=lambda kv: -kv[1])[:10]:
        print("  %7.1fs  %s" % (v, k2))
    bad = failed > 0 or bool(problems) or any(s != 0 for s in statuses)
    print("\nRESULT: %s   (logs: %s)" % ("FAIL" if bad else "PASS", outdir))
    return 1 if bad else 0


if __name__ == "__main__":
    c = sys.argv[1]
    if c == "pack":
        pack(sys.argv[2], sys.argv[3], int(sys.argv[4]), sys.argv[5])
    elif c == "summary":
        sys.exit(summary(sys.argv[2], sys.argv[3], sys.argv[4], int(sys.argv[5]), [int(x) for x in sys.argv[6].split(",")]))
