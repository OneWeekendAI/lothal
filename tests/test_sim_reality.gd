class_name TestSimReality
extends RefCounted
## One test per reference aircraft per case (not a loop), so the failure count says WHICH aircraft
## left the band. Run by tools/run_sim_reality.sh, deliberately NOT registered in tests/run_tests.gd:
## the harness is expected to be red until SR1 closes the gaps it finds, and a red suite there
## would block unrelated work. Each in-band test is paired with a "flight valid" test, because an
## out-of-band number from a flight that lost control or hit the time cap is a controller finding,
## not a physics one.

## `gate` false (default): a published-time band check is context, so only its flight-validity test is
## asserted here (the out-of-band row is printed as a [WARN] by the runner). `gate` true: the band
## tests are asserted too.
static var gate := false


static func run(p_gate: bool = false) -> Array:
	gate = p_gate
	var out: Array = []
	out.append_array(_mavic_hover())
	out.append_array(_mavic_cruise())
	out.append_array(_evoque_hover())
	out.append_array(_chimera_hover())
	out.append_array(_capacity_cut_leaves_band())
	return out


static func _check(id: String, case_name: String) -> Array:
	var row := SimRealityHarness.row(SimRealityHarness.find_reference(id), case_name)
	var res: Dictionary = row["result"]
	var label := "%s %s" % [id, case_name]
	var checks: Array = [
		TestResult.new("%s: flight ends in a battery cutoff" % label, bool(res["valid"]),
			"ended by: %s after %.1f min, max tilt %.1f deg" % [res["ended_by"], res["time_min"], res["max_tilt_deg"]])]
	if bool(row["context"]) and not gate:
		return checks
	checks.append(
		TestResult.new("%s: sim time within %.0f%% of published" % [label, row["band_pct"]], bool(row["in_band"]),
			"sim %.1f min vs published %.1f min (%+.1f%%)" % [row["sim_min"], row["published_min"], row["err_pct"]]))
	return checks


static func _mavic_hover() -> Array:
	return _check("mavic_3m", "hover")

static func _mavic_cruise() -> Array:
	return _check("mavic_3m", "cruise")

static func _evoque_hover() -> Array:
	return _check("nazgul_evoque_f5_v2_5in", "hover")

static func _chimera_hover() -> Array:
	return _check("chimera7_pro_v2_7in", "hover")


## The fail-proof, as a test: a pack with 30% less capacity must shorten every flight by about 30%,
## which is far outside the 10% band. Counts how many cases LEAVE the band relative to the
## full-capacity copy; the harness is blind if fewer than two do. (Cases already out of band at full
## capacity count only if their error moves by more than the band.)
static func _capacity_cut_leaves_band() -> Array:
	var moved := 0
	var details: Array = []
	for ref in SimRealityHarness.load_references():
		for case_name in ref["cases"]:
			var full := SimRealityHarness.row(ref, case_name, 1.0)
			var cut := SimRealityHarness.row(ref, case_name, 0.7)
			var shift := absf(float(cut["err_pct"]) - float(full["err_pct"]))
			if shift > float(full["band_pct"]):
				moved += 1
			details.append("%s/%s %+.0f%% -> %+.0f%%" % [ref["id"], case_name, full["err_pct"], cut["err_pct"]])
	return [TestResult.new("harness is not blind: a 30% capacity cut moves at least two cases by more than the band",
		moved >= 2, "%d moved: %s" % [moved, "; ".join(details)])]
