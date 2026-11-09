class_name TestSimRealityLogic
extends RefCounted
## SR0.1: the harness's reporting and exit-code rules, on synthetic rows (no flights, runs in
## milliseconds). One test per case. Owner decision 2026-11-10: published whole-aircraft rows are
## CONTEXT; out of band is a flagged warning and does not fail the run, except under --gate.
##
## MUTATION RECORD (each check shown to fail with its fix removed, 2026-11-10):
##   - exit_code ignoring `context` (every out-of-band row fails)      -> "context row out of band exits 0" red
##   - exit_code ignoring `gate`                                        -> "gate makes a context row fail" red
##   - exit_code skipping the non-context test                          -> "a non-context row out of band fails" red
##   - format_table header without the real_world / published(opt) text -> the two column tests red
##   - SR0.2: version blanked / field_flags constant / capacity_scale constant / 80%-used text dropped / trail line not printed -> one red each (5/5)
##   - context_warnings returning nothing                               -> "context row out of band is flagged" red


static func _row(context: bool, in_band: bool, valid: bool = true, real_world: Variant = null) -> Dictionary:
	return {
		"id": "synthetic", "name": "Synthetic", "case": "hover",
		"published_min": 37.0, "sim_min": 30.0, "err_pct": -18.9, "band_pct": 10.0,
		"in_band": in_band, "tag": "published (optimistic)" if context else "measured",
		"context": context, "real_world": real_world, "fitted": "", "published_auw_g": 951.0,
		"result": {"valid": valid, "ended_by": "cell voltage cutoff", "auw_g": 951.0, "mean_power_w": 200.0,
			"mean_current_a": 13.0, "t80_min": 24.0, "wall_s": 1.0},
	}


static func run() -> Array:
	var out: Array = []
	out.append(_columns_published_opt())
	out.append(_columns_real_world())
	out.append(_real_world_value_shown())
	out.append(_context_flagged())
	out.append(_in_band_not_flagged())
	out.append(_context_exits_zero())
	out.append(_gate_fails_context())
	out.append(_non_context_fails())
	out.append(_invalid_flight_fails())
	out.append(_failed_test_fails())
	out.append(_trail_printed())
	out.append(_trail_keys_nonempty())
	out.append(_trail_follows_field_flag())
	out.append(_trail_follows_capacity())
	out.append(_convention_printed())
	return out


static func _trail() -> Dictionary:
	return SimRealityHarness.input_trail(SimRealityHarness.find_reference("mavic_3m"), 1.0, {})


static func _trail_printed() -> TestResult:
	var r := _row(true, false)
	r["trail"] = _trail()
	var txt := SimRealityHarness.format_table([r])
	return TestResult.new("table prints an input trail line per row", txt.contains("input trail:") and txt.contains("git_sha="), txt)


static func _trail_keys_nonempty() -> TestResult:
	var t := _trail()
	var empty: PackedStringArray = []
	for k in ["build", "version", "rust_model", "git_sha", "field_flags"]:
		if str(t.get(k, "")) == "" or str(t.get(k)) == "unknown":
			empty.append(k)
	return TestResult.new("trail keys build/version/rust_model/git_sha/field_flags are all known", empty.is_empty(), "empty: %s" % ", ".join(empty))


static func _trail_follows_field_flag() -> TestResult:
	var ref := SimRealityHarness.find_reference("mavic_3m")
	var a := SimRealityHarness.input_trail(ref, 1.0, {})
	var b := SimRealityHarness.input_trail(ref, 1.0, {"avionics": false})
	return TestResult.new("changing a field-physics flag changes the trail", a["field_flags"] != b["field_flags"], "%s vs %s" % [a["field_flags"], b["field_flags"]])


static func _trail_follows_capacity() -> TestResult:
	var ref := SimRealityHarness.find_reference("mavic_3m")
	var a := SimRealityHarness.input_trail(ref, 1.0, {})
	var b := SimRealityHarness.input_trail(ref, 0.7, {})
	return TestResult.new("changing the capacity scale changes the trail", a["capacity_scale"] != b["capacity_scale"], "")


static func _convention_printed() -> TestResult:
	var txt := SimRealityHarness.format_table([_row(true, false)])
	return TestResult.new("80 percent-used convention printed beside time-to-empty", txt.contains("time-to-empty") and txt.contains("80%-used convention"), txt)


static func _header() -> String:
	return SimRealityHarness.format_table([_row(true, false)]).split("\n")[0]


static func _columns_published_opt() -> TestResult:
	return TestResult.new("table has a 'published(opt)' column", _header().contains("published(opt)"), _header())


static func _columns_real_world() -> TestResult:
	return TestResult.new("table has a 'real_world' column", _header().contains("real_world"), _header())


static func _real_world_value_shown() -> TestResult:
	var rw := {"min_low": 25.0, "min_high": 30.0, "tag": "owner field experience"}
	var line := SimRealityHarness.format_table([_row(true, false, true, rw)]).split("\n")[1]
	return TestResult.new("real_world range is printed in the row", line.contains("25-30"), line)


static func _context_flagged() -> TestResult:
	var w := SimRealityHarness.context_warnings([_row(true, false)])
	return TestResult.new("context row out of band is flagged as a [WARN] line",
		w.size() == 1 and w[0].begins_with("[WARN]"), str(w))


static func _in_band_not_flagged() -> TestResult:
	var w := SimRealityHarness.context_warnings([_row(true, true)])
	return TestResult.new("a context row in band is not flagged", w.is_empty(), str(w))


static func _context_exits_zero() -> TestResult:
	var code := SimRealityHarness.exit_code([_row(true, false)], 0, false)
	return TestResult.new("context row out of band exits 0", code == 0, "exit %d" % code)


static func _gate_fails_context() -> TestResult:
	var code := SimRealityHarness.exit_code([_row(true, false)], 0, true)
	return TestResult.new("--gate makes a context row out of band fail", code == 1, "exit %d" % code)


static func _non_context_fails() -> TestResult:
	var code := SimRealityHarness.exit_code([_row(false, false)], 0, false)
	return TestResult.new("a non-context row out of band fails without --gate", code == 1, "exit %d" % code)


static func _invalid_flight_fails() -> TestResult:
	var code := SimRealityHarness.exit_code([_row(true, false, false)], 0, false)
	return TestResult.new("an invalid flight fails even for a context row", code == 1, "exit %d" % code)


static func _failed_test_fails() -> TestResult:
	var code := SimRealityHarness.exit_code([_row(true, true)], 1, false)
	return TestResult.new("a failed test fails the run", code == 1, "exit %d" % code)
