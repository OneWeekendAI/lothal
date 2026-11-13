#!/usr/bin/env python3
"""Build the CropMerge decision data from runs.csv (phase D of the cross-check).

Reads  DATA/runs.csv, repro.csv, bom.csv   (DATA = landingpage/docs/lothal/plans/cropmerge/crosscheck/data)
Writes DATA/configs.csv, requirements.csv, data_dictionary.csv, cropmerge_data.xlsx
Appends 3 farm-run rows to repro.csv (idempotent).

No simulation is run here: every number is copied from or computed on runs.csv rows.
Usage: python build_cropmerge_data.py DATA_DIR      (xlsx needs openpyxl)
"""
import csv, os, sys
from collections import defaultdict

DATA = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
    "~/Desktop/OneWeekendAI/landingpage/docs/lothal/plans/cropmerge/crosscheck/data")
P = lambda n: os.path.join(DATA, n)

KEY_NOFIELD = ["sensor", "pack_ah", "pack_s", "pack_wh", "rgb_addon", "rtk", "remote_id", "height_m",
               "front", "side", "speed_mps", "speed_source", "reserve_pct"]
KEY = KEY_NOFIELD + ["field"]
OK_END = {"landed_at_reserve", "completed"}
BIG = "3000x1000"
FARM = "2000x1012"


def f(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None


def r1(v, n=2):
    return "" if v is None else round(v, n)


def B(v):  # bool -> TRUE/FALSE text, None -> blank
    if v is None or v == "":
        return ""
    if isinstance(v, str):
        return {"true": "TRUE", "false": "FALSE"}.get(v.lower(), "")
    return "TRUE" if v else "FALSE"


def load(name):
    with open(P(name), newline="") as fh:
        return list(csv.DictReader(fh))


def norm(row):
    """Config key value; the Mavic has no catalog pack, so its 0.0 Ah means unknown -> blank."""
    d = {k: row[k] for k in KEY}
    if row["sensor"] == "mavic" and f(row["pack_ah"]) in (None, 0.0):
        d["pack_ah"] = ""
    return d


def line_stop(row):
    return "sortie stopped at a line boundary" in row["warnings"]


def write(name, cols, rows):
    with open(P(name), "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c, "") for c in cols})


# ---------------------------------------------------------------- configs
runs = load("runs.csv")
groups = defaultdict(list)
for r in runs:
    groups[tuple(norm(r)[k] for k in KEY)].append(r)


def seedkey(r):
    return (int(r["seed"] or 0), runs.index(r))


CFG_COLS = ["config_id", "label", "sensor", "pack_ah", "pack_s", "pack_wh", "rgb_addon", "rtk", "remote_id",
            "height_m", "front_overlap", "side_overlap", "speed_mps", "speed_source", "reserve_pct", "field",
            "field_acres", "farm_run", "run_id_calm", "n_calm_runs", "n_seeds_calm", "mass_kg", "twr", "gsd_cm",
            "trigger_ok", "flight_min_per_sortie", "flight_min_seed_spread", "left_pct", "ended_by",
            "line_boundary_stop", "acres_per_sortie", "acres_per_sortie_seed_spread", "mapped_acres",
            "acres_batt_extrapolated", "packs500_extrapolated", "farm_sorties_actual", "packs500_actual_whole",
            "packs500_actual_drawn", "farm_total_flight_min", "farm_complete", "pack_limit_a",
            "peak_current_a_calm", "current_margin_pct_calm", "n_wind_runs", "wind_mph_tested",
            "peak_current_a_worst_wind", "current_margin_pct_worst_wind", "min_voltage_v_worst",
            "worst_wind_flight_min_10to20mph", "worst_wind_flight_run_id", "worst_wind_acres_per_sortie_10to20mph",
            "worst_wind_acres_run_id", "worst_wind_flight_min_25mph", "wind_runs_not_landed",
            "meets_30min_calm", "meets_100_125_acres_at_60m_7565", "meets_500ac_in_5_packs_actual",
            "wind_10to20_all_landed", "wind_10to20_meets_30min", "rank_group", "rank_in_group"]

configs = []
for i, (k, rows) in enumerate(sorted(groups.items(), key=lambda kv: (
        kv[0][-1], kv[0][0], f(kv[0][7]) or 0, kv[0][8], kv[0][10], kv[0][1], kv[0][12], kv[0][6]))):
    d = dict(zip(KEY, k))
    calm = sorted([r for r in rows if r["wind_dir"] == "calm"], key=seedkey)
    wind = [r for r in rows if r["wind_dir"] != "calm"]
    rep = calm[0] if calm else sorted(wind, key=seedkey)[0]
    farm = d["field"] == FARM
    c = {"config_id": "K%03d" % (i + 1), "sensor": d["sensor"], "pack_ah": f(d["pack_ah"]) if d["pack_ah"] else "",
         "pack_s": f(rep["pack_s"]), "pack_wh": f(d["pack_wh"]), "rgb_addon": B(d["rgb_addon"]),
         "rtk": B(d["rtk"]), "remote_id": B(d["remote_id"]), "height_m": f(d["height_m"]),
         "front_overlap": f(d["front"]), "side_overlap": f(d["side"]), "speed_mps": f(d["speed_mps"]),
         "speed_source": d["speed_source"], "reserve_pct": f(d["reserve_pct"]), "field": d["field"],
         "field_acres": f(rep["field_acres"]), "farm_run": B(farm),
         "run_id_calm": rep["run_id"] if calm else "", "n_calm_runs": len(calm),
         "n_seeds_calm": len({r["seed"] for r in calm}), "mass_kg": f(rep["mass_kg"]), "twr": f(rep["twr"]),
         "gsd_cm": f(rep["gsd_cm"]), "trigger_ok": B(rep["trigger_ok"]), "pack_limit_a": f(rep["pack_limit_a"])}
    for x in ("pack_s",):
        c[x] = "" if c[x] is None else c[x]
    c["label"] = "%s %s%s%s%s h%g %g/%g %gm/s(%s) r%g %s" % (
        d["sensor"], ("%gAh-%gS" % (f(d["pack_ah"]), f(rep["pack_s"]))) if d["pack_ah"] and rep["pack_s"] else "stock-pack",
        " +rgb" if d["rgb_addon"] == "true" else "", "" if d["rtk"] != "false" else " no-rtk",
        " +rid" if d["remote_id"] == "true" else "", f(d["height_m"]), f(d["front"]) * 100,
        f(d["side"]) * 100, f(d["speed_mps"]), d["speed_source"], f(d["reserve_pct"]), d["field"])
    if calm:
        fl = [f(r["flight_min"]) for r in calm]
        ap = [f(r["acres_per_sortie"]) for r in calm]
        if c["n_seeds_calm"] > 1:
            c["flight_min_seed_spread"] = r1(max(fl) - min(fl))
            c["acres_per_sortie_seed_spread"] = r1(max(ap) - min(ap))
        c.update(left_pct=f(rep["left_pct"]), ended_by=rep["ended_by"], line_boundary_stop=B(line_stop(rep)),
                 acres_per_sortie=f(rep["acres_per_sortie"]), mapped_acres=f(rep["mapped_acres"]),
                 acres_batt_extrapolated=f(rep["acres_batt"]), packs500_extrapolated=f(rep["packs500"]),
                 peak_current_a_calm=f(rep["peak_current_a"]), meets_30min_calm=B(rep["meets_30min"]))
        if farm:
            c.update(farm_sorties_actual=int(f(rep["sorties"])), packs500_actual_whole=int(f(rep["sorties"])),
                     packs500_actual_drawn=f(rep["packs_used"]), farm_total_flight_min=f(rep["flight_min"]),
                     farm_complete=B(rep["farm_complete"]))
            c["meets_500ac_in_5_packs_actual"] = B(rep["farm_complete"] == "true" and f(rep["sorties"]) <= 5)
        else:
            c["flight_min_per_sortie"] = f(rep["flight_min"])
        if c["pack_limit_a"] and c["peak_current_a_calm"]:
            c["current_margin_pct_calm"] = r1((c["pack_limit_a"] - c["peak_current_a_calm"]) / c["pack_limit_a"] * 100, 1)
        if (f(d["height_m"]), f(d["front"]), f(d["side"])) == (60.0, 0.75, 0.65) and not farm:
            c["meets_100_125_acres_at_60m_7565"] = B(c["acres_per_sortie"] >= 100)
    c["n_wind_runs"] = len(wind)
    if wind:
        c["wind_mph_tested"] = " ".join("%g" % v for v in sorted({f(r["wind_mph"]) for r in wind}))
        pk = max(wind, key=lambda r: f(r["peak_current_a"]))
        c["peak_current_a_worst_wind"] = f(pk["peak_current_a"])
        if c["pack_limit_a"]:
            c["current_margin_pct_worst_wind"] = r1((c["pack_limit_a"] - c["peak_current_a_worst_wind"]) / c["pack_limit_a"] * 100, 1)
        band = [r for r in wind if 10 <= f(r["wind_mph"]) <= 20]
        if band:
            wf = min(band, key=lambda r: (f(r["flight_min"]), r["run_id"]))
            wa = min(band, key=lambda r: (f(r["acres_per_sortie"]), r["run_id"]))
            c.update(worst_wind_flight_min_10to20mph=f(wf["flight_min"]), worst_wind_flight_run_id=wf["run_id"],
                     worst_wind_acres_per_sortie_10to20mph=f(wa["acres_per_sortie"]), worst_wind_acres_run_id=wa["run_id"],
                     wind_10to20_all_landed=B(all(r["ended_by"] in OK_END for r in band)),
                     wind_10to20_meets_30min=B(f(wf["flight_min"]) >= 30) if not line_stop(wf) else "")
        w25 = [f(r["flight_min"]) for r in wind if f(r["wind_mph"]) == 25]
        if w25:
            c["worst_wind_flight_min_25mph"] = min(w25)
        c["wind_runs_not_landed"] = sum(r["ended_by"] not in OK_END for r in wind)
    c["min_voltage_v_worst"] = min(f(r["min_voltage_v"]) for r in rows if f(r["min_voltage_v"]) is not None)
    c["_key"] = k
    configs.append(c)

# rank inside stated groups
RANK_RULE = ("3000x1000 field, 25 % reserve, calm, meets_30min_calm TRUE, trigger_ok TRUE; "
             "ranked by acres_per_sortie (high first) within sensor x height; ties (equal acres = same line count) -> more calm seeds, then RTK fitted, then longer flight, then config_id")
pool = defaultdict(list)
for c in configs:
    if (c["field"] == BIG and c["reserve_pct"] == 25.0 and c.get("meets_30min_calm") == "TRUE"
            and c["trigger_ok"] == "TRUE" and c.get("acres_per_sortie", "") != ""):
        pool[(c["sensor"], c["height_m"])].append(c)
for (s, h), cs in pool.items():
    cs.sort(key=lambda c: (-c["acres_per_sortie"], -c["n_seeds_calm"], c["rtk"] != "TRUE",
                           -c["flight_min_per_sortie"], c["config_id"]))
    for n, c in enumerate(cs, 1):
        c["rank_group"] = "%s r25 calm 30min-met %s h%g" % (BIG, s, h)
        c["rank_in_group"] = n
write("configs.csv", CFG_COLS, configs)

# ---------------------------------------------------------------- requirements
by_id = {r["run_id"]: r for r in runs}
cfg_of_run = {}
for c in configs:
    for r in groups[c["_key"]]:
        cfg_of_run[r["run_id"]] = c
nofield = lambda c: c["_key"][:-1]


def sibling(c, field):
    for o in configs:
        if nofield(o) == nofield(c) and o["field"] == field and o["n_calm_runs"]:
            return o
    return None


cands = []  # (candidate_id, role, config used for calm evidence, farm config or None)
base_k = [c for c in configs if c["run_id_calm"] == "base_1000"][0]
cands.append(("baseline_sheet_field", "sheet baseline on the field the sheets really used (1000x500)", base_k))
cands.append(("baseline", "sheet baseline on the 3000x1000 test field", sibling(base_k, BIG)))
for c in configs:
    if c["field"] == FARM:
        cands.append(("farm_" + c["run_id_calm"].replace("n_farm_", ""), "real multi-pack farm run config", c))
for (s, h), cs in sorted(pool.items(), key=lambda kv: (kv[0][0], kv[0][1])):
    if s == "mavic":
        continue
    cands.append(("best_h%g_%s" % (h, s), "best by acres_per_sortie at %g m, %s (rule in README)" % (h, s), cs[0]))
# merge candidates that are the same aircraft+mission settings
merged, seen = [], {}
for cid, role, c in cands:
    nk = nofield(c)
    if cid != "baseline_sheet_field" and nk in seen and seen[nk][0] != "baseline_sheet_field":
        seen[nk][1].append(role + " [" + cid + "]")
        continue
    item = [cid, [role], c]
    merged.append(item)
    if cid != "baseline_sheet_field":
        seen[nk] = item
    else:
        seen.setdefault(("sheet",), item)

REQ_COLS = ["candidate_id", "candidate_role", "config_id", "run_id", "ask_id", "ask_text", "target_min",
            "target_max", "unit", "measured_value", "measured_basis", "met", "margin", "note"]
req = []
SENSOR_PAY = {
    "rededge_p": dict(bands=(True, "published", "MicaSense RedEdge-P: G/R/RE/NIR (+blue, pan)"),
                      light=(True, "published", "DLS 2 in the RedEdge-P kit; its 54 g is in the simulated mass")),
    "sentera_6x": dict(bands=(True, "published", "Sentera 6X: G/R/RE/NIR + blue, plus 20 MP RGB"),
                       light=(None, "not_modelled", "Sentera light sensor: model and mass not found, not counted in mass")),
    "mavic": dict(bands=(True, "published", "DJI Mavic 3M multispectral G/R/RE/NIR (maker spec; not compared in the sheets)"),
                  light=(True, "published", "Mavic 3M sunlight sensor is built in (maker spec)")),
}

for cid, roles, c in merged:
    role = "; ".join(roles)
    calm = c if c["field"] != FARM else (sibling(c, BIG) or c)
    farm = c if c["field"] == FARM else sibling(c, FARM)
    allrows = [r for o in configs if nofield(o) == nofield(c) for r in groups[o["_key"]]]
    if cid == "baseline_sheet_field":
        allrows = groups[c["_key"]]
    wind = [r for r in allrows if r["wind_dir"] != "calm" and 10 <= f(r["wind_mph"]) <= 20]
    same = [r for r in wind if r["field"] == calm["field"]]
    wind = same or wind  # prefer wind runs on the calm evidence field; else any field (named in the note)

    def add(ask_id, text, tmin, tmax, unit, val, basis, met, margin, note, src, cfg=None):
        cfg = cfg or (cfg_of_run[src] if src in cfg_of_run else calm)
        req.append(dict(candidate_id=cid, candidate_role=role, config_id=cfg["config_id"], run_id=src,
                        ask_id=ask_id, ask_text=text, target_min=tmin, target_max=tmax, unit=unit,
                        measured_value=val, measured_basis=basis, met=B(met) if basis not in ("not_modelled", "not_run") else "",
                        margin=margin, note=note))

    # A1 flight time
    if calm["field"] != FARM:
        rid = calm["run_id_calm"]
        fm = calm["flight_min_per_sortie"]
        met = True if calm["meets_30min_calm"] == "TRUE" else (False if calm["meets_30min_calm"] == "FALSE" else None)
        note = "calm, field %s, %g %% left, ended %s" % (calm["field"], calm["left_pct"], calm["ended_by"])
        if met is None:
            note += "; flight_min is cut short by a line-boundary stop or a finished field, so endurance is not measured"
        add("A1_flight_30min", "Flight time 30+ min", 30, "", "min", fm, "simulated_actual", met,
            r1(fm - 30, 1), note, rid)
    else:
        add("A1_flight_30min", "Flight time 30+ min", 30, "", "min", "", "not_run", None, "",
            "no single-sortie calm run for these settings; farm_total_flight_min is a multi-sortie total", c["run_id_calm"])
    # A2 acres per battery at 60 m 75/65
    ap = calm["acres_per_sortie"]
    geo = (calm["height_m"], calm["front_overlap"], calm["side_overlap"]) == (60.0, 0.75, 0.65)
    note = ("acres actually mapped in one sortie (%s field); extrapolated acres_batt = %g, NOT achievable when the sortie "
            "stops at a whole line" % (calm["field"], calm["acres_batt_extrapolated"]))
    if not geo:
        note = ("ask is defined at 60 m 75/65; this config flies %g m %g/%g, value shown for comparison only; " %
                (calm["height_m"], calm["front_overlap"] * 100, calm["side_overlap"] * 100)) + note
    add("A2_acres_per_battery", "Acres per battery 100-125 at 60 m, 75/65 (more is also fine)", 100, 125, "acres",
        ap, "simulated_actual", (ap >= 100) if geo else None, r1(ap - 100, 1), note, calm["run_id_calm"])
    if not geo:
        req[-1]["met"] = ""
    # A3 500 acres in 4-5 packs
    if farm:
        n = farm["farm_sorties_actual"]
        add("A3_500ac_4to5_packs", "500-acre farm in 3-4 swaps (4-5 packs)", 4, 5, "packs (whole, actual swaps)", n,
            "simulated_actual", n <= 5, 5 - n,
            "real multi-pack run on 2000x1012 m (500.2 acres), swap time not counted; %g pack-fractions drawn; "
            "single-sortie extrapolation for the same settings = %s packs" % (farm["packs500_actual_drawn"],
                                                                            calm["packs500_extrapolated"]),
            farm["run_id_calm"], farm)
    else:
        add("A3_500ac_4to5_packs", "500-acre farm in 3-4 swaps (4-5 packs)", 4, 5, "packs", "", "simulated_extrapolated",
            None, "", "no farm run for these settings; extrapolated packs500 = %g (understates: farm runs needed more "
            "whole packs than extrapolated)" % calm["packs500_extrapolated"], calm["run_id_calm"])
    # A4 wind 10-20 mph
    if wind:
        wf = min(wind, key=lambda r: (f(r["flight_min"]), r["run_id"]))
        wa = min(wind, key=lambda r: (f(r["acres_per_sortie"]), r["run_id"]))
        pk = max(wind, key=lambda r: f(r["peak_current_a"]))
        mph = " ".join("%g" % v for v in sorted({f(r["wind_mph"]) for r in wind}))
        fields = " ".join(sorted({r["field"] for r in wind}))
        ctx = "%d runs, %s mph, dirs %s, field %s" % (len(wind), mph, " ".join(sorted({r["wind_dir"] for r in wind})), fields)
        add("A4a_wind_worst_flight", "Fly in 10-20 mph wind: worst flight time (30 min ask)", 30, "", "min",
            f(wf["flight_min"]), "simulated_actual", f(wf["flight_min"]) >= 30, r1(f(wf["flight_min"]) - 30, 1),
            "worst of %s: %s mph %s seed %s" % (ctx, wf["wind_mph"], wf["wind_dir"], wf["seed"]), wf["run_id"])
        if line_stop(wf):
            req[-1]["met"] = ""
            req[-1]["note"] += ("; this run stopped at a line boundary with %s %% left, so the short time is line "
                                "quantisation, not wind; endurance in wind not measured" % wf["left_pct"])
        add("A4b_wind_worst_acres", "Fly in 10-20 mph wind: worst acres per sortie", "", "", "acres",
            f(wa["acres_per_sortie"]), "simulated_actual", None, "",
            "no target in the ask; calm value %s; worst of %s: %s mph %s seed %s" % (
                calm["acres_per_sortie"], ctx, wa["wind_mph"], wa["wind_dir"], wa["seed"]), wa["run_id"])
        req[-1]["met"] = ""
        bad = [r for r in wind if r["ended_by"] not in OK_END]
        add("A4c_wind_lost_control", "Fly in 10-20 mph wind: runs that did not land normally", "", 0, "runs",
            len(bad), "simulated_actual", len(bad) == 0, -len(bad),
            ctx + "; counted = ended_by not landed_at_reserve/completed; the sim has no separate loss-of-control flag",
            wf["run_id"])
        lim = f(pk["pack_limit_a"])
        add("A4d_wind_peak_current", "Fly in 10-20 mph wind: worst peak current vs pack limit", "", lim if lim else "", "A",
            f(pk["peak_current_a"]), "simulated_actual", (f(pk["peak_current_a"]) <= lim) if lim else None,
            r1(lim - f(pk["peak_current_a"]), 1) if lim else "",
            ("pack limit %g A (cell rating, estimated); ESC rating not checked" % lim) if lim else
            "pack limit unknown (no catalog entry for this pack)", pk["run_id"])
        if not lim:
            req[-1]["met"] = ""
    else:
        for a, t in (("A4a_wind_worst_flight", "worst flight time"), ("A4b_wind_worst_acres", "worst acres per sortie"),
                     ("A4c_wind_lost_control", "runs that did not land normally"),
                     ("A4d_wind_peak_current", "worst peak current vs pack limit")):
            add(a, "Fly in 10-20 mph wind: " + t, "", "", "", "", "not_run", None, "",
                "no wind runs for these settings", calm["run_id_calm"])
    # A5 payload
    sp = SENSOR_PAY[c["sensor"]]
    rid = calm["run_id_calm"]
    add("A5a_bands", "Payload: G/R/RE/NIR bands", "", "", "", "", sp["bands"][1], sp["bands"][0], "", sp["bands"][2], rid)
    if c["sensor"] == "rededge_p":
        rgb = c["rgb_addon"] == "TRUE"
        add("A5b_rgb", "Payload: RGB", "", "", "", "", "published", rgb, "",
            "Sony RX0 II add-on fitted (mass in sim; mass from a search summary)" if rgb else
            "RedEdge-P has no RGB; add-on not fitted in this config", rid)
    else:
        add("A5b_rgb", "Payload: RGB", "", "", "", "", "published", True, "",
            "20 MP RGB built into the sensor (maker spec)", rid)
    add("A5c_light_sensor", "Payload: light sensor", "", "", "", "", sp["light"][1], sp["light"][0], "", sp["light"][2], rid)
    if c["sensor"] == "mavic":
        add("A5d_rtk", "Payload: optional RTK", "", "", "", "", "not_modelled", None, "",
            "Mavic RTK module not modelled", rid)
    else:
        rtk = c["rtk"] == "TRUE"
        add("A5d_rtk", "Payload: optional RTK", "", "", "", "", "published", rtk, "",
            ("Here3+ RTK rover fitted (51.8 g, in sim mass); RTK base or network not modelled" if rtk else
             "RTK not fitted in this config"), rid)
    # A6 Remote ID
    if c["sensor"] == "mavic":
        add("A6_remote_id", "Remote ID", "", "", "", "", "not_modelled", None, "",
            "Mavic Remote ID not modelled; check DJI's FAA declaration", rid)
    else:
        on = c["remote_id"] == "TRUE"
        add("A6_remote_id", "Remote ID", "", "", "", "", "published", on, "",
            "Dronetag Beacon 16 g (published) in sim mass" if on else
            "no Remote ID module in this config; adding the 16 g module: see n_rid1_* rows (effect below line quantisation)", rid)
    for a, t, n in (("A7_part107", "Part 107 operation", "pilot certification and operations; not a simulation question"),
                    ("A8_may_2027", "Flying by May 2027", "no schedule was made"),
                    ("A9_grid_missions", "ArduPilot / PX4 grid missions",
                     "standard ground-station feature; not flown or tested" if c["sensor"] != "mavic" else
                     "Mavic flies DJI's own planner, not ArduPilot/PX4")):
        add(a, t, "", "", "", "", "not_modelled", None, "", n, rid)
write("requirements.csv", REQ_COLS, req)

# ---------------------------------------------------------------- repro farm rows
repro_cols = ["sheet", "section", "claim", "doc_value", "rerun_value", "delta_pct", "verdict", "note"]
repro = load("repro.csv")
farm_rows = [
    ("RESULTS_SHEET", "Ask by ask", "Our drone: 500-acre farm needs 6.1 packs (4.5-7.0)", 6.1, "n_farm_base"),
    ("RESULTS_SHEET", "Ask by ask", "Mavic 3M: 500-acre farm needs 6.2 packs (4.6-7.1)", 6.2, "n_farm_mavic60"),
    ("EMAIL", "Honest gaps", "500-acre farm needs about 6 packs", 6.0, "n_farm_base"),
]
for sheet, sec, claim, doc, rid in farm_rows:
    if any(x["claim"] == claim for x in repro):
        continue
    r = by_id[rid]
    n = int(f(r["sorties"]))
    repro.append(dict(sheet=sheet, section=sec, claim=claim, doc_value=doc, rerun_value=n,
                      delta_pct=round((n - doc) / doc * 100, 1), verdict="wrong",
                      note="real multi-pack run %s on 2000x1012 m (500.2 acres): %d whole packs (sorties), %s pack-fractions "
                           "drawn, %s min total, swap time not counted. The sheet extrapolated one sortie; each sortie "
                           "stops at a whole line so packs are only part-used." % (rid, n, r["packs_used"], r["flight_min"])))
write("repro.csv", repro_cols, repro)

# ---------------------------------------------------------------- data dictionary
RUNS_DOC = {
    "run_id": ("", "text", "unique run name; prefix c_=combo, w_=wind, n_=new (phase C), else sheet repro", "spec echo", ""),
    "group": ("", "text", "repro | combo | wind | new", "spec echo", ""),
    "sensor": ("", "text", "rededge_p | sentera_6x | mavic (DJI Mavic 3M reference)", "spec echo", ""),
    "pack_ah": ("Ah", "number", "pack capacity", "spec echo", "Mavic rows: 0.0 or blank = no catalog pack entry; treat as unknown"),
    "pack_wh": ("Wh", "number", "pack energy", "spec echo", "Li-ion packs are ESTIMATED (21700 cell maths)"),
    "rgb_addon": ("", "boolean", "Sony RX0 II RGB add-on fitted", "spec echo", "Sony mass from a search summary"),
    "rtk": ("", "boolean", "Here3+ RTK rover fitted", "spec echo", "no RTK base modelled"),
    "remote_id": ("", "boolean", "Dronetag Beacon Remote ID module fitted (16 g)", "spec echo", "blank on Mavic rows"),
    "height_m": ("m", "number", "survey height above ground", "spec echo", "flat terrain only"),
    "front": ("fraction", "number", "forward photo overlap (0.75 = 75 %)", "spec echo", ""),
    "side": ("fraction", "number", "side photo overlap", "spec echo", ""),
    "speed_mps": ("m/s", "number", "planned survey speed", "sim-measured", "app caps speed at 15 m/s"),
    "speed_source": ("", "text", "auto_1s = 1 s trigger stand-in; auto_camera_fps = camera max rate; manual = set", "spec echo", ""),
    "reserve_pct": ("%", "number", "landing reserve; RTH when the pack reaches it", "spec echo", ""),
    "field": ("m x m", "text", "simulated field size", "spec echo", "acres per sortie depends on field shape"),
    "field_acres": ("acres", "number", "field area", "computed in post", ""),
    "wind_mph": ("mph", "number", "mean wind", "spec echo", ""),
    "wind_dir": ("", "text", "calm | along | across | quartering the survey lines", "spec echo", ""),
    "gust_frac": ("fraction", "number", "gust strength as a fraction of mean wind", "spec echo", ""),
    "seed": ("", "integer", "random seed for gusts/noise", "spec echo", ""),
    "mass_kg": ("kg", "number", "take-off mass", "sim-measured", "airframe parts are placeholders (see bom)"),
    "twr": ("ratio", "number", "thrust-to-weight", "sim-measured", ""),
    "flight_min": ("min", "number", "time in the air; on farm rows the total over all sorties", "sim-measured",
                   "line-quantised: a sortie stops at a whole line, so this can understate endurance"),
    "left_pct": ("%", "number", "pack left at landing", "sim-measured", ""),
    "ended_by": ("", "text", "landed_at_reserve | completed | battery_empty_in_flight", "sim-measured", ""),
    "energy_wh": ("Wh", "number", "energy drawn", "sim-measured", ""),
    "acres_batt": ("acres", "number", "acres per battery EXTRAPOLATED to the reserve from the fraction used", "computed in post",
                   "EXTRAPOLATION, often not achievable (sortie stops at a whole line)"),
    "acres_low": ("acres", "number", "extrapolation at reserve + 10 points", "computed in post", "heuristic range, not statistical"),
    "acres_high": ("acres", "number", "extrapolation to 0 % reserve", "computed in post", "heuristic range, not statistical"),
    "mapped_acres": ("acres", "number", "acres actually covered", "sim-measured", ""),
    "packs500": ("packs", "number", "500 / acres_batt (extrapolated)", "computed in post", "understates real farm packs"),
    "packs500_low": ("packs", "number", "500 / acres_high", "computed in post", "extrapolated"),
    "packs500_high": ("packs", "number", "500 / acres_low", "computed in post", "extrapolated"),
    "gsd_cm": ("cm/pixel", "number", "ground sample distance (pixel size)", "computed in post", "from published sensor specs"),
    "trigger_interval_s": ("s", "number", "time between photos", "sim-measured", ""),
    "required_fps": ("1/s", "number", "capture rate the plan needs", "computed in post", ""),
    "camera_max_fps": ("1/s", "number", "sensor max capture rate", "published", ""),
    "trigger_ok": ("", "boolean", "required rate within camera max", "computed in post", "motion blur not modelled"),
    "peak_current_a": ("A", "number", "peak pack current", "sim-measured", "ESC rating not checked"),
    "pack_limit_a": ("A", "number", "pack continuous limit (cells x C rating)", "spec echo", "estimated; blank for Mavic"),
    "min_voltage_v": ("V", "number", "lowest loaded pack voltage", "sim-measured", ""),
    "hover_power_w": ("W", "number", "hover electrical power", "sim-measured", ""),
    "cruise_power_w": ("W", "number", "survey cruise electrical power", "sim-measured", ""),
    "meets_30min": ("", "boolean", "flight_min >= 30; blank when line-quantised or field completed", "computed in post", ""),
    "meets_4to5_packs": ("", "boolean", "packs500 (extrapolated) <= 5", "computed in post", "uses the extrapolation"),
    "meets_100_125_acres": ("", "boolean", "acres_batt (extrapolated) in 100-125", "computed in post", "uses the extrapolation"),
    "pack_s": ("cells", "integer", "series cell count", "spec echo", "6S: ESC voltage rating not checked"),
    "speed_cap_mps": ("m/s", "number", "app speed cap", "spec echo", ""),
    "sorties": ("packs", "integer", "packs swapped in (whole packs)", "sim-measured", "farm rows: real swaps; swap time not counted"),
    "packs_used": ("packs", "number", "sum of pack fractions drawn", "sim-measured", ""),
    "farm_complete": ("", "boolean", "multi-pack run finished the farm (only set when max_sorties > 1)", "sim-measured", ""),
    "acres_per_sortie": ("acres", "number", "mapped_acres / sorties", "computed in post", "the ACHIEVED figure; use this for decisions"),
    "warnings": ("", "text", "runner warnings, ' | ' separated", "sim-measured", ""),
}
CFG_DOC = {
    "config_id": ("", "text", "config key K###, one per distinct settings set", "computed in post", ""),
    "label": ("", "text", "readable summary of the settings", "computed in post", ""),
    "front_overlap": ("fraction", "number", "= runs.front", "spec echo", ""),
    "side_overlap": ("fraction", "number", "= runs.side", "spec echo", ""),
    "farm_run": ("", "boolean", "config is a real multi-pack 2000x1012 farm run", "computed in post", ""),
    "run_id_calm": ("", "text", "representative calm run (lowest seed, then first in runs.csv); calm columns copy it",
                    "computed in post", "blank when the config has only wind runs"),
    "n_calm_runs": ("runs", "integer", "calm runs of this config", "computed in post", ""),
    "n_seeds_calm": ("seeds", "integer", "distinct seeds among calm runs", "computed in post", ""),
    "flight_min_per_sortie": ("min", "number", "calm single-sortie flight time (blank on farm rows)", "sim-measured", "line-quantised"),
    "flight_min_seed_spread": ("min", "number", "max - min over calm seeds (only when > 1 seed)", "computed in post", ""),
    "line_boundary_stop": ("", "boolean", "runner warned the sortie stopped at a line boundary with > reserve+10 % left",
                           "sim-measured", "flight_min understates endurance"),
    "acres_per_sortie_seed_spread": ("acres", "number", "max - min over calm seeds", "computed in post", ""),
    "acres_batt_extrapolated": ("acres", "number", "= runs.acres_batt", "computed in post", "EXTRAPOLATION, not achievable"),
    "packs500_extrapolated": ("packs", "number", "= runs.packs500", "computed in post", "EXTRAPOLATION, understates"),
    "farm_sorties_actual": ("packs", "integer", "farm rows: sorties flown", "sim-measured", "swap time not counted"),
    "packs500_actual_whole": ("packs", "integer", "farm rows: whole packs needed for 500.2 acres", "sim-measured", ""),
    "packs500_actual_drawn": ("packs", "number", "farm rows: pack fractions drawn", "sim-measured", ""),
    "farm_total_flight_min": ("min", "number", "farm rows: total air time over all sorties", "sim-measured", "swap time excluded"),
    "peak_current_a_calm": ("A", "number", "calm peak current", "sim-measured", "ESC rating not checked"),
    "current_margin_pct_calm": ("%", "number", "(pack_limit_a - peak) / pack_limit_a x 100", "computed in post", "pack limit estimated"),
    "n_wind_runs": ("runs", "integer", "wind runs of this config (any speed)", "computed in post", ""),
    "wind_mph_tested": ("mph", "text", "wind speeds run, space separated", "computed in post", ""),
    "peak_current_a_worst_wind": ("A", "number", "highest peak current over all wind runs", "sim-measured", ""),
    "current_margin_pct_worst_wind": ("%", "number", "margin at the worst wind peak", "computed in post", ""),
    "min_voltage_v_worst": ("V", "number", "lowest min_voltage_v over all runs of the config", "sim-measured", ""),
    "worst_wind_flight_min_10to20mph": ("min", "number", "lowest flight_min over 10-20 mph wind runs", "sim-measured", "line-quantised"),
    "worst_wind_flight_run_id": ("", "text", "run giving the worst wind flight time", "computed in post", ""),
    "worst_wind_acres_per_sortie_10to20mph": ("acres", "number", "lowest acres_per_sortie over 10-20 mph wind runs", "sim-measured", ""),
    "worst_wind_acres_run_id": ("", "text", "run giving the worst wind acres", "computed in post", ""),
    "worst_wind_flight_min_25mph": ("min", "number", "lowest flight_min at 25 mph (outside the ask)", "sim-measured", ""),
    "wind_runs_not_landed": ("runs", "integer", "wind runs not ending landed_at_reserve/completed", "sim-measured",
                             "no separate loss-of-control flag exists in the sim"),
    "meets_30min_calm": ("", "boolean", "= runs.meets_30min of the calm run", "computed in post", "blank = unknown"),
    "meets_100_125_acres_at_60m_7565": ("", "boolean", "acres_per_sortie >= 100; only for 60 m 75/65 single-sortie configs",
                                        "computed in post", "achieved acres, not extrapolated"),
    "meets_500ac_in_5_packs_actual": ("", "boolean", "farm completed in <= 5 whole packs; farm rows only", "computed in post", ""),
    "wind_10to20_all_landed": ("", "boolean", "every 10-20 mph wind run landed normally", "computed in post", ""),
    "wind_10to20_meets_30min": ("", "boolean", "worst 10-20 mph flight_min >= 30; blank when that run stopped at a line boundary (time not set by wind)", "computed in post", "line-quantised"),
    "rank_group": ("", "text", "ranking group; blank = not ranked. Rule: " + RANK_RULE, "computed in post", ""),
    "rank_in_group": ("", "integer", "1 = most acres per sortie in its group", "computed in post", "differences under ~1 line are noise"),
}
for k in ("sensor", "pack_ah", "pack_s", "pack_wh", "rgb_addon", "rtk", "remote_id", "height_m", "speed_mps",
          "speed_source", "reserve_pct", "field", "field_acres", "mass_kg", "twr", "gsd_cm", "trigger_ok", "left_pct",
          "ended_by", "acres_per_sortie", "mapped_acres", "farm_complete", "pack_limit_a"):
    m = RUNS_DOC[k]
    CFG_DOC.setdefault(k, (m[0], m[1], "copied from the representative calm run: " + m[2], m[3], m[4]))
CFG_DOC["pack_ah"] = ("Ah", "number", "pack capacity", "spec echo", "blank for the Mavic (no catalog pack)")
REQ_DOC = {
    "candidate_id": ("", "text", "candidate config (see README for how candidates were chosen)", "computed in post", ""),
    "candidate_role": ("", "text", "why this candidate is in the table", "computed in post", ""),
    "config_id": ("", "text", "configs.csv row the evidence comes from", "computed in post", ""),
    "run_id": ("", "text", "runs.csv row the measured value comes from", "computed in post", ""),
    "ask_id": ("", "text", "customer ask code (A1..A9)", "spec echo", "asks from RESULTS_SHEET 'Ask by ask'"),
    "ask_text": ("", "text", "the customer ask in words", "spec echo", ""),
    "target_min": ("see unit", "number", "lower bound of the ask", "spec echo", ""),
    "target_max": ("see unit", "number", "upper bound of the ask", "spec echo", ""),
    "unit": ("", "text", "unit of target and measured value", "spec echo", ""),
    "measured_value": ("see unit", "number", "value for this candidate; blank when not modelled / not run", "sim-measured", ""),
    "measured_basis": ("", "text", "simulated_actual | simulated_extrapolated | published | arithmetic | not_modelled | not_run (no run exists for these settings)",
                       "computed in post", ""),
    "met": ("", "boolean", "ask met; blank when not modelled, not run, no target, or not determinable", "computed in post", ""),
    "margin": ("see unit", "number", "measured - target_min (or target_max - measured)", "computed in post", "under ~1 line is noise"),
    "note": ("", "text", "context, evidence and caveats", "computed in post", ""),
}
REPRO_DOC = {
    "sheet": ("", "text", "document the claim is from", "published", ""),
    "section": ("", "text", "section of that document", "published", ""),
    "claim": ("", "text", "the claim as written", "published", ""),
    "doc_value": ("", "mixed", "value in the document", "published", "some cells are text (e.g. a field size)"),
    "rerun_value": ("", "mixed", "value from the rerun", "sim-measured", "some cells are text"),
    "delta_pct": ("%", "number", "(rerun - doc) / doc x 100", "computed in post", ""),
    "verdict": ("", "text", "match | drift | wrong | not_reproducible", "computed in post", ""),
    "note": ("", "text", "evidence and run_ids", "computed in post", ""),
}
BOM_DOC = {
    "variant": ("", "text", "build variant", "spec echo", ""),
    "role": ("", "text", "part role", "spec echo", ""),
    "part_id": ("", "text", "catalog id", "spec echo", ""),
    "part_name": ("", "text", "part name", "spec echo", ""),
    "qty": ("count", "integer", "quantity", "spec echo", ""),
    "unit_mass_g": ("g", "number", "mass of one part", "spec echo", "airframe rows are FPV-class placeholders"),
    "total_mass_g": ("g", "number", "qty x unit mass", "computed in post", ""),
    "power_w": ("W", "number", "electrical power of the part", "spec echo", ""),
    "source_tag": ("", "text", "PUBLISHED | ESTIMATED | unverified | computed", "spec echo", ""),
    "source_note": ("", "text", "source URL or reasoning", "spec echo", ""),
}
DD_COLS = ["file", "column", "unit", "type", "meaning", "source", "caveat"]
DD_DOC = {c: ("", "text", "data dictionary field: " + c, "computed in post", "") for c in DD_COLS}
dd = []
for fname, cols, doc in (("runs.csv", list(runs[0].keys()), RUNS_DOC), ("configs.csv", CFG_COLS, CFG_DOC),
                         ("requirements.csv", REQ_COLS, REQ_DOC), ("repro.csv", repro_cols, REPRO_DOC),
                         ("bom.csv", list(load("bom.csv")[0].keys()), BOM_DOC), ("data_dictionary.csv", DD_COLS, DD_DOC)):
    for col in cols:
        u, t, m, s, cv = doc[col]
        dd.append(dict(file=fname, column=col, unit=u, type=t, meaning=m, source=s, caveat=cv))
write("data_dictionary.csv", DD_COLS, dd)

# ---------------------------------------------------------------- xlsx
README = [
    "CropMerge data. Sheets: configs = one row per distinct setting set (decision table); requirements = customer ask x candidate; runs = every simulated run; repro = sheet claims vs rerun; bom = per-part mass; data_dictionary = every column.",
    "Filter: use the header autofilter. In configs, filter field=3000x1000 and reserve_pct=25, then sort acres_per_sortie; rank_group/rank_in_group give the pre-made ranking. Best-per-height rule: " + RANK_RULE + ".",
    "1. acres_batt / acres_batt_extrapolated / packs500 are EXTRAPOLATIONS and often not achievable (a sortie stops at a whole line: e.g. n_rid0_t1red120 maps 241.4 acres but reports acres_batt 300.4). Decide on acres_per_sortie, mapped_acres and farm-run packs.",
    "2. Line-boundary quantisation dominates small effects: +16 g Remote ID changed one config from 241.4 to 213.0 mapped acres (n_rid0_t1red120 vs n_rid1_t1red120). Single-run differences under about one line (~10 % of a pack on 3 km lines) are noise.",
    "3. Real multi-pack farm runs (2000x1012 m, 500.2 acres) need MORE whole packs than the sheets' extrapolation: baseline 8 vs 6.1 (n_farm_base); see the n_farm_* rows and configs.packs500_actual_whole.",
    "4. The sheets' field '1500 x 500 m (185 acres)' is wrong: their numbers come from 1000x500 (123.6 acres); on 1500x500 the baseline flies 29.2 min and misses 30 min (base_1500). The DJI published-conditions check and the earlier Mavic wind rows are not reproducible (repro sheet).",
    "5. bom airframe rows are FPV-class catalog parts (FC 8 g, ESC 12 g, VTX, FPV antenna) tagged unverified/estimated on a ~1.9 kg mapper peaking at 40-72 A: a mass placeholder, NOT a buyable parts list. ESC current and voltage ratings (esp. 6S) are not checked.",
    "6. Everything is simulation: nothing was built or flown. There are no prices.",
    "Blank cell = unknown, not run or not modelled (never 0). Booleans are TRUE/FALSE. Units are in data_dictionary.",
]


def build_xlsx():
    from openpyxl import Workbook
    from openpyxl.utils import get_column_letter
    wb = Workbook()
    ws = wb.active
    ws.title = "README"
    for i, line in enumerate(README, 1):
        ws.cell(row=i, column=1, value=line)
    ws.column_dimensions["A"].width = 160
    types = {(d["file"], d["column"]): d["type"] for d in dd}

    def conv(fname, col, v):
        t = types[(fname, col)]
        if v == "" or v is None:
            return None
        if t == "boolean":
            return {"true": True, "false": False}[str(v).lower()]
        if t in ("number", "integer"):
            x = float(v)
            return int(x) if t == "integer" else x
        if t == "mixed":
            x = f(v)
            return x if x is not None else str(v)
        return str(v)

    for sheet, fname in (("configs", "configs.csv"), ("requirements", "requirements.csv"), ("runs", "runs.csv"),
                         ("repro", "repro.csv"), ("bom", "bom.csv"), ("data_dictionary", "data_dictionary.csv")):
        rows = load(fname)
        cols = list(rows[0].keys())
        ws = wb.create_sheet(sheet)
        ws.append(cols)
        for r in rows:
            ws.append([conv(fname, c, r[c]) for c in cols])
        ws.freeze_panes = "A2"
        ws.auto_filter.ref = "A1:%s%d" % (get_column_letter(len(cols)), len(rows) + 1)
        for j, c in enumerate(cols, 1):
            w = max([len(c)] + [len(str(r[c])) for r in rows[:200]])
            ws.column_dimensions[get_column_letter(j)].width = max(8, min(w + 2, 50))
    wb.save(P("cropmerge_data.xlsx"))


build_xlsx()
print("configs", len(configs), "requirements", len(req), "repro", len(repro), "dictionary", len(dd))
