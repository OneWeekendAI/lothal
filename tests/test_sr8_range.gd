class_name TestSr8Range
extends RefCounted
## SR8 uncertainty. SR8.1 tolerance fields (src/autopilot/tolerances.gd) and the runner hooks they drive (mass_scale, drag_scale,
## esc_loss_scale, pack_temp_c in MissionRunner). SR8.2 / SR8.3 (Monte Carlo, dominant input) follow in this file. One TestResult per case.
## Flights: five_inch, capacity_scale 0.15, seed 11, 3 m/s wind with 1.5 m/s gusts; hover_endurance (and a 1-lap cruise_loop for drag).
## Hand figures: hover power goes as mass^1.5, so +10 percent mass shortens a hover by 1 - 1.1^-1.5 = 13.3 percent (band 9-16 percent: the pack
## sags and the motors leave the ideal line). Direction-and-order checks for temperature (cold pack: -20 C), ESC loss (x2) and drag (x2, cruise).
## FAIL-PROOFS (observed 2026-11-10): TL1 a default tag blanked: the tag and defaults cases FAIL. TL2 edit leaves the default tag: the edit case FAILS.
## TL3 mass hook removed: the mass case FAILS (126.3 s -> 126.3 s). TL4 pack temperature hook removed: the temperature case FAILS. TL5 ESC hook removed: the ESC case FAILS.
## TL6 drag hook removed: the drag case FAILS.

static var _cache: Dictionary = {}


static func _fly(extra: Dictionary = {}, mission: String = Mission.HOVER_ENDURANCE) -> Dictionary:
	var key := var_to_str([extra, mission])
	if not _cache.has(key):
		var p := {"class_id": "five_inch", "mission": mission, "seed": 11, "capacity_scale": 0.15, "wind_speed_mps": 3.0, "wind_from_deg": 60.0, "gust_mps": 1.5}
		if mission == Mission.CRUISE_LOOP:
			p["laps"] = 1
		for k in extra:
			p[k] = extra[k]
		_cache[key] = MissionRunner.run(p)
	return _cache[key]


static func run() -> Array:
	return [
		_every_tolerance_tagged(),
		_defaults_load(),
		_edit_marks_user(),
		_edit_back_to_default(),
		_edit_does_not_mutate(),
		_problem_detector_can_fail(),
		_hook_defaults_identical(),
		_hook_mass(),
		_hook_temperature(),
		_hook_esc(),
		_hook_drag(),
		_mc_flat_when_nothing_varies(),
		_mc_capacity_range(),
		_mc_wired_mass(),
		_mc_wired_temperature(),
		_mc_same_seed_same_range(),
		_mc_other_seed_differs(),
		_mc_widening_widens(),
		_mc_draws_independent_of_widths(),
		_mc_doubling_runs(),
		_mc_figure(),
		_dominant_mass(),
		_dominant_capacity(),
		_dominant_hand_spread(),
		_dominant_shares(),
		_dominant_none_when_flat(),
		_crop_labelled_ranges(),
		_crop_batteries(),
		_crop_dominant_consistent(),
	]


static func _every_tolerance_tagged() -> TestResult:
	var t := Tolerances.defaults()
	var bad: Array[String] = []
	for n in Tolerances.NAMES:
		if String(t.fields[n]["tag"]) not in Tolerances.TAGS or String(t.fields[n]["source"]) == "":
			bad.append(n)
	return TestResult.new("sr8 tolerances: every default has a tag in {measured, published, estimated} and a source line", bad.is_empty() and t.problems().is_empty(), str(bad) + str(t.problems()))


static func _defaults_load() -> TestResult:
	var t := Tolerances.defaults()
	var ok: bool = t.fields.size() == Tolerances.NAMES.size() and t.half_width("capacity_pct") == 5.0 and t.half_width("wind_seeds") == 5.0 and t.half_width("wind_speed_mps") == 0.0
	for n in Tolerances.NAMES:
		ok = ok and not bool(t.fields[n]["edited"]) and String(t.fields[n]["tag"]) == "estimated"
	return TestResult.new("sr8 tolerances: the seven defaults load (capacity +-5, 5 wind seeds, wind speed off), all estimated and unedited", ok, str(t.fields.keys()))


static func _edit_marks_user() -> TestResult:
	var t := Tolerances.defaults().with_half("mass_pct", 10.0)
	var f: Dictionary = t.fields["mass_pct"]
	return TestResult.new("sr8 tolerances: editing mass to +-10 percent marks it edited, tag user, default tag kept", bool(f["edited"]) and f["tag"] == "user" and f["default_tag"] == "estimated" and f["half"] == 10.0, str(f))


static func _edit_back_to_default() -> TestResult:
	var t := Tolerances.defaults().with_half("mass_pct", 10.0).with_half("mass_pct", 3.0)
	var f: Dictionary = t.fields["mass_pct"]
	return TestResult.new("sr8 tolerances: setting a field back to its default clears 'edited' and restores its tag", not bool(f["edited"]) and f["tag"] == "estimated", str(f))


static func _edit_does_not_mutate() -> TestResult:
	var a := Tolerances.defaults()
	var b := a.with_half("drag_pct", 50.0)
	return TestResult.new("sr8 tolerances: with_half returns a copy, the original keeps 20 percent drag", a.half_width("drag_pct") == 20.0 and b.half_width("drag_pct") == 50.0, "%s / %s" % [a.half_width("drag_pct"), b.half_width("drag_pct")])


static func _problem_detector_can_fail() -> TestResult:
	var t := Tolerances.defaults()
	t.fields["drag_pct"]["default_tag"] = "guess"
	t.fields["mass_pct"]["source"] = ""
	return TestResult.new("sr8 tolerances: the checker reports a bad tag and a missing source (it can fail)", t.problems().size() == 2, str(t.problems()))


static func _hook_defaults_identical() -> TestResult:
	var a := _fly()
	var b := _fly({"mass_scale": 1.0, "drag_scale": 1.0, "esc_loss_scale": 1.0, "pack_temp_c": 25.0})
	return TestResult.new("sr8 hooks: mass / drag / ESC scales of 1 and 25 C give the same flight as leaving them out (bit for bit in the figures)",
		float(a["flight_time_s"]) == float(b["flight_time_s"]) and float(a["energy_wh"]) == float(b["energy_wh"]), "%s vs %s s" % [a["flight_time_s"], b["flight_time_s"]])


static func _hook_mass() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"mass_scale": 1.1})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: +10 percent mass shortens the hover by 9-16 percent (hand 13.3 percent from mass^1.5)", change < -0.09 and change > -0.16, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_temperature() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"pack_temp_c": 5.0})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: a 5 C pack (20 C colder) shortens the hover by 5-20 percent", change < -0.05 and change > -0.20, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_esc() -> TestResult:
	var a := float(_fly()["flight_time_s"])
	var b := float(_fly({"esc_loss_scale": 2.0})["flight_time_s"])
	var change := b / a - 1.0
	return TestResult.new("sr8 hooks: doubling the ESC loss shortens the hover by 0.5-5 percent", change < -0.005 and change > -0.05, "%.1f s -> %.1f s (%.1f percent)" % [a, b, change * 100.0])


static func _hook_drag() -> TestResult:
	var a := _fly({}, Mission.CRUISE_LOOP)
	var b := _fly({"drag_scale": 2.0}, Mission.CRUISE_LOOP)
	var wa := float(a["wh_per_min"])
	var wb := float(b["wh_per_min"])
	return TestResult.new("sr8 hooks: doubling body drag raises a cruise's Wh per minute by 5-25 percent", wb / wa - 1.0 > 0.05 and wb / wa - 1.0 < 0.25, "%.4f -> %.4f Wh/min (%.1f percent)" % [wa, wb, (wb / wa - 1.0) * 100.0])


# ---------------------------------------------------------------- SR8.2 Monte Carlo
## Metric: hover flight_time_s, which is deterministic in the pack capacity (time ~ capacity), mass^-1.5 and pack temperature. Uniform draws over +-5 percent
## capacity put the 10th-90th percentile at +-4 percent of the median: width/mid 0.08 in the limit (band 0.04-0.12 for 6 draws).
## n = 6 draws (12 for the doubling case); each draw is a 2.5 s hover flight.
## FAIL-PROOFS (observed 2026-11-10): MC1 capacity factor not applied: 3 FAIL (capacity range, other seed, widening; all flat at 126.3 s). MC2 mass hook ignored: the mass case FAILS (width 0.000).
## MC3 pack temperature ignored: the temperature case FAILS (width 0.001). MC4 generator seeded with a clock: 5 FAIL (same seed, widening, independence, doubling...).
## MC5 draws only made for non-zero tolerances: the independence case FAILS.
const MC_N := 6
static var _mc: Dictionary = {}


static func _base() -> Dictionary:
	return {"class_id": "five_inch", "mission": Mission.HOVER_ENDURANCE, "seed": 11, "capacity_scale": 0.15, "wind_speed_mps": 3.0, "wind_from_deg": 60.0, "gust_mps": 1.5}


static func _only(name: String, half: float) -> Tolerances:
	return Tolerances.defaults().zeroed().with_half(name, half)


static func _mc_run(label: String, tol: Tolerances, n: int, master: int) -> Dictionary:
	var key := "%s|%d|%d" % [label, n, master]
	if not _mc.has(key):
		_mc[key] = MonteCarlo.run(_base(), tol, n, master)
	return _mc[key]


static func _width(mc: Dictionary) -> float:
	return (float(mc["high"]) - float(mc["low"])) / float(mc["mid"])


static func _mc_flat_when_nothing_varies() -> TestResult:
	var mc := _mc_run("zero", Tolerances.defaults().zeroed(), MC_N, 1)
	return TestResult.new("sr8 monte carlo: with every tolerance zero the range is flat (low = mid = high) -- the control for a not-wired input",
		float(mc["low"]) == float(mc["high"]) and float(mc["mid"]) > 100.0, "low %.3f mid %.3f high %.3f s" % [mc["low"], mc["mid"], mc["high"]])


static func _mc_capacity_range() -> TestResult:
	var mc := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var nominal := float(TestSr8Range._fly()["flight_time_s"])
	return TestResult.new("sr8 monte carlo: +-5 percent capacity gives a 10-90 range 4-12 percent wide around a median within 3 percent of the nominal hover",
		_width(mc) > 0.04 and _width(mc) < 0.12 and absf(float(mc["mid"]) / nominal - 1.0) < 0.03 and float(mc["low"]) < float(mc["mid"]) and float(mc["mid"]) < float(mc["high"]),
		"low %.1f mid %.1f high %.1f s (width %.3f), nominal %.1f s" % [mc["low"], mc["mid"], mc["high"], _width(mc), nominal])


static func _mc_wired_mass() -> TestResult:
	var mc := _mc_run("mass", _only("mass_pct", 10.0), MC_N, 1)
	return TestResult.new("sr8 monte carlo: a mass tolerance alone (+-10 percent) widens the range (over 4 percent)", _width(mc) > 0.04, "width %.3f" % _width(mc))


static func _mc_wired_temperature() -> TestResult:
	var mc := _mc_run("temp", _only("temperature_c", 10.0), MC_N, 1)
	return TestResult.new("sr8 monte carlo: a temperature tolerance alone (+-10 C) widens the range (over 3 percent)", _width(mc) > 0.03, "width %.3f" % _width(mc))


static func _mc_same_seed_same_range() -> TestResult:
	var a := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var b := MonteCarlo.run(_base(), _only("capacity_pct", 5.0), MC_N, 1)
	return TestResult.new("sr8 monte carlo: the same master seed gives the same draws and the same low / mid / high",
		JSON.stringify(a["draws"]) == JSON.stringify(b["draws"]) and a["low"] == b["low"] and a["mid"] == b["mid"] and a["high"] == b["high"], "%.4f/%.4f/%.4f" % [b["low"], b["mid"], b["high"]])


static func _mc_other_seed_differs() -> TestResult:
	var a := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var b := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 2)
	return TestResult.new("sr8 monte carlo: another master seed draws differently (different low and high)", a["low"] != b["low"] and a["high"] != b["high"], "%.3f vs %.3f" % [a["low"], b["low"]])


static func _mc_widening_widens() -> TestResult:
	var a := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var b := _mc_run("cap10", _only("capacity_pct", 10.0), MC_N, 1)
	var ratio := _width(b) / _width(a)
	return TestResult.new("sr8 monte carlo: doubling the capacity tolerance (same draws) roughly doubles the range (ratio 1.6-2.4)", ratio > 1.6 and ratio < 2.4, "widths %.3f -> %.3f, ratio %.2f" % [_width(a), _width(b), ratio])


static func _mc_draws_independent_of_widths() -> TestResult:
	var a := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var b := _mc_run("cap10", _only("capacity_pct", 10.0), MC_N, 1)
	var z := _mc_run("zero", Tolerances.defaults().zeroed(), MC_N, 1)
	var same := true
	for i in MC_N:
		same = same and JSON.stringify(a["draws"][i]["u"]) == JSON.stringify(b["draws"][i]["u"]) and JSON.stringify(a["draws"][i]["u"]) == JSON.stringify(z["draws"][i]["u"])
	return TestResult.new("sr8 monte carlo: the unit draws are the same whatever the widths (widening one tolerance never reshuffles another)", same, "6 draws compared across three tolerance sets")


static func _mc_doubling_runs() -> TestResult:
	var a := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var b := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N * 2, 1)
	var mid := float(b["mid"])
	var first_same := true
	for i in MC_N:
		first_same = first_same and JSON.stringify(a["draws"][i]) == JSON.stringify(b["draws"][i])
	var d_low := absf(float(a["low"]) - float(b["low"])) / mid
	var d_high := absf(float(a["high"]) - float(b["high"])) / mid
	return TestResult.new("sr8 monte carlo: doubling 6 -> 12 runs keeps the first 6 draws and moves low and high by less than 2.5 percent of the median (stated bound)",
		first_same and d_low < 0.025 and d_high < 0.025, "low moved %.2f %%, high moved %.2f %% of mid" % [d_low * 100.0, d_high * 100.0])


static func _mc_figure() -> TestResult:
	var mc := _mc_run("cap5", _only("capacity_pct", 5.0), MC_N, 1)
	var f := MonteCarlo.as_figure(mc, "s")
	return TestResult.new("sr8 monte carlo: the range converts to a result figure with low <= value <= high, tag estimated and the percentile wording",
		float(f["low"]) <= float(f["value"]) and float(f["value"]) <= float(f["high"]) and f["tag"] == "estimated" and String(f["range"]).contains("percentile"), str(f))


# ---------------------------------------------------------------- SR8.3 dominant input and the CropMerge worked example
## One-at-a-time on the hover flight time (deterministic in capacity, mass, temperature). Hand: capacity +-5 percent moves a hover time by 2 x 5 = 10 percent.
## The CropMerge example uses five_inch as a STAND-IN for the (not yet built) mapping class, on a 70 x 50 m survey; acres per battery is extrapolated.
## FAIL-PROOFS (observed 2026-11-10): DM1 ranking by the smaller spread: 4 FAIL (both dominant cases, shares/sorted, cropmerge). DM2 the +1 corner not applied: the hand-spread
## and cropmerge cases FAIL (the two dominant cases still pass, mass dominates either way). DM3 shares not normalised: the shares case FAILS. DM4 batteries range not inverted: the batteries case FAILS.
static var _oat: Dictionary = {}


static func _oat_run(label: String, tol: Tolerances) -> Dictionary:
	if not _oat.has(label):
		_oat[label] = Sensitivity.one_at_a_time(_base(), tol, "flight_time_s")
	return _oat[label]


static func _entry(rep: Dictionary, name: String) -> Dictionary:
	for e in rep["entries"]:
		if e["input"] == name:
			return e
	return {}


static func _dominant_mass() -> TestResult:
	var rep := _oat_run("cap5_mass30", Tolerances.defaults().zeroed().with_half("capacity_pct", 5.0).with_half("mass_pct", 30.0))
	return TestResult.new("sr8 dominant: with mass inflated to +-30 percent beside capacity +-5, mass is named dominant and ranked first", rep["dominant"] == "mass_pct" and rep["entries"][0]["input"] == "mass_pct",
		"dominant %s; spreads capacity %.1f s, mass %.1f s" % [rep["dominant"], _entry(rep, "capacity_pct")["spread"], _entry(rep, "mass_pct")["spread"]])


static func _dominant_capacity() -> TestResult:
	var rep := _oat_run("cap40_mass3", Tolerances.defaults().zeroed().with_half("capacity_pct", 40.0).with_half("mass_pct", 3.0))
	return TestResult.new("sr8 dominant: with capacity inflated to +-40 percent beside mass +-3, capacity is named dominant", rep["dominant"] == "capacity_pct",
		"dominant %s; spreads capacity %.1f s, mass %.1f s" % [rep["dominant"], _entry(rep, "capacity_pct")["spread"], _entry(rep, "mass_pct")["spread"]])


static func _dominant_hand_spread() -> TestResult:
	var rep := _oat_run("cap5_mass30", Tolerances.defaults().zeroed().with_half("capacity_pct", 5.0).with_half("mass_pct", 30.0))
	var e := _entry(rep, "capacity_pct")
	var pct := float(e["spread_pct_of_nominal"])
	return TestResult.new("sr8 dominant: capacity +-5 percent moves the hover time by 9-11 percent (hand 10 percent: time goes with capacity)", pct > 9.0 and pct < 11.0, "%.2f percent of the nominal %.1f s" % [pct, rep["nominal"]])


static func _dominant_shares() -> TestResult:
	var rep := _oat_run("cap5_mass30", Tolerances.defaults().zeroed().with_half("capacity_pct", 5.0).with_half("mass_pct", 30.0))
	var sum := 0.0
	var sorted_ok := true
	var unflown_ok := true
	for i in rep["entries"].size():
		var e: Dictionary = rep["entries"][i]
		sum += float(e["share"])
		if i > 0 and float(e["spread"]) > float(rep["entries"][i - 1]["spread"]):
			sorted_ok = false
		if float(e["half_width"]) == 0.0 or (e["input"] == "wind_seeds"):
			unflown_ok = unflown_ok and int(e["flights"]) == 0 and float(e["spread"]) == 0.0
	return TestResult.new("sr8 dominant: shares add to 1, entries are sorted by spread, and zero tolerances (and a single wind seed) are listed with 0 flights and 0 spread",
		absf(sum - 1.0) < 1e-9 and sorted_ok and unflown_ok and rep["entries"].size() == Tolerances.NAMES.size(), "share sum %.6f, sorted %s, unflown ok %s" % [sum, str(sorted_ok), str(unflown_ok)])


static func _dominant_none_when_flat() -> TestResult:
	var rep := _oat_run("zero", Tolerances.defaults().zeroed())
	return TestResult.new("sr8 dominant: with every tolerance zero nothing is named (dominant empty, total spread 0)", rep["dominant"] == "" and float(rep["total_spread"]) == 0.0, str(rep["dominant"]))


static var _crop: Dictionary = {}


static func _crop_run() -> Dictionary:
	if _crop.is_empty():
		var field := PackedVector2Array([Vector2(30, 0), Vector2(100, 0), Vector2(100, 50), Vector2(30, 50)])
		_crop = Sensitivity.cropmerge_example("five_inch", field, 100.0, 6, 1)
	return _crop


static func _crop_labelled_ranges() -> TestResult:
	var c := _crop_run()
	var a: Dictionary = c["acres_per_battery"]
	var ok: bool = String(c["label"]).contains("STAND-IN") and String(c["label"]).contains("EXTRAPOLATED") and float(a["low"]) < float(a["mid"]) and float(a["mid"]) < float(a["high"]) \
		and a["tag"] == "estimated" and c["wind_mph"] == [10.0, 20.0] and float(c["capacity_pct"]) == 5.0 and float(a["low"]) > 0.0
	return TestResult.new("sr8 cropmerge: the worked example is labelled stand-in and extrapolated and gives acres per battery as low < mid < high (estimated)", ok,
		"%.2f / %.2f / %.2f acres per battery" % [a["low"], a["mid"], a["high"]])


static func _crop_batteries() -> TestResult:
	var c := _crop_run()
	var a: Dictionary = c["acres_per_battery"]
	var b: Dictionary = c["batteries_per_farm"]
	return TestResult.new("sr8 cropmerge: batteries for a 100-acre farm = 100 / acres per battery with the range inverted (low from the high acres)",
		absf(float(b["value"]) - 100.0 / float(a["mid"])) < 1e-9 and absf(float(b["low"]) - 100.0 / float(a["high"])) < 1e-9 and absf(float(b["high"]) - 100.0 / float(a["low"])) < 1e-9 and float(b["low"]) < float(b["high"]),
		"%.1f (%.1f-%.1f) batteries" % [b["value"], b["low"], b["high"]])


static func _crop_dominant_consistent() -> TestResult:
	var c := _crop_run()
	var d: Dictionary = c["dominant"]
	var cap := _entry(d, "capacity_pct")
	var wind := _entry(d, "wind_speed_mps")
	var named_is_larger: bool = (d["dominant"] == "capacity_pct") == (float(cap["spread"]) >= float(wind["spread"]))
	var cap_pct := float(cap["spread_pct_of_nominal"])
	return TestResult.new("sr8 cropmerge: the dominant input is the one with the larger spread, and capacity +-5 percent moves acres per battery by 8-12 percent (hand 10: acres per battery goes with capacity)",
		named_is_larger and d["dominant"] in ["capacity_pct", "wind_speed_mps"] and cap_pct > 8.0 and cap_pct < 12.0,
		"dominant %s; capacity spread %.2f percent (%.2f acres), wind spread %.2f acres" % [d["dominant"], cap_pct, cap["spread"], wind["spread"]])
