class_name TestSr6Flow
extends RefCounted
## L1.1 MissionFlow: a saved design flown through MissionRunner. Short flights (capacity_scale 0.3 (the sr4 suite's short pack), hover_endurance), seed 1.
## Cases: (1) a design saved to a dict and read back flies with no opts: finite flight_time_s > 0, record has build/mission/seed.
## (2) a reserve_pct override changes the result and appears in result.params.fields. (3) a design with another battery has a different
## build_fingerprint than the class default (the saved build is flown, not the class seed). (4) an unknown mission returns the runner's
## error shape (ended_by "error", error text), no crash.
## FAIL-PROOFS observed 2026-11-10: RED A: MissionFlow drops opts.fields -> only the reserve_pct case FAILS (reserve 0 -> 0, flight_time 271.5 -> 271.5 s). RED B: MissionFlow does not pass the session build (class seed flown) -> only the saved-build case FAILS (identical fingerprints). Both GREEN after restoring (4/4). First run at capacity_scale 0.05 was not_flown (reserve exceeds usable energy), hence 0.3.

const SCALE := 0.3


static func run() -> Array:
	return [_default_flight(), _field_override(), _saved_build_flown(), _unknown_mission()]


static func _session(cls: String) -> DesignSession:
	var catalog := PartsCatalog.load_default()
	var d := DesignFile.to_dict(DesignSession.default_for_class(cls), "t")
	return DesignFile.from_dict(d, catalog)["session"] as DesignSession


static func _opts(extra: Dictionary = {}) -> Dictionary:
	var o := {"capacity_scale": SCALE}
	o.merge(extra, true)
	return o


static func _default_flight() -> TestResult:
	var r: Dictionary = MissionFlow.run(_session("five_inch"), _opts())
	var res: Dictionary = r["result"]
	var rec: Dictionary = r["record"]
	var t := float(res.get("flight_time_s", 0.0))
	var ok := is_finite(t) and t > 0.0 and rec.has("build") and rec.has("mission") and rec.has("seed") \
		and String(res["mission"]) == "hover_endurance"
	return TestResult.new("sr6 flow: a saved five_inch design flies hover_endurance with no opts; record has build/mission/seed", ok, "flight_time_s=%.1f ended=%s %s" % [t, res.get("ended_by"), str(res.get("warnings"))])


static func _field_override() -> TestResult:
	var s := _session("five_inch")
	var base: Dictionary = MissionFlow.run(s, _opts())
	var def_reserve := float(base["result"]["params"]["fields"]["reserve_pct"]["value"])
	var edited: Dictionary = MissionFlow.run(s, _opts({"fields": {"reserve_pct": 15.0}}))
	var f: Dictionary = edited["result"]["params"]["fields"]
	var shown := float(f["reserve_pct"]["value"])
	var tb := float(base["result"]["flight_time_s"])
	var te := float(edited["result"]["flight_time_s"])
	return TestResult.new("sr6 flow: a reserve_pct override changes the result and shows in params.fields", shown == 15.0 and def_reserve != 15.0 and not is_equal_approx(tb, te),
		"reserve %.0f -> %.0f, flight_time %.1f -> %.1f s" % [def_reserve, shown, tb, te])


static func _saved_build_flown() -> TestResult:
	var base := _session("five_inch")
	var other_id := ""
	for e in PartsCatalog.load_default().list_category("battery"):
		if String(e["part_id"]) != String(base.selection["battery"]) and String(e["part_id"]).begins_with("battery_4s"):
			other_id = String(e["part_id"])
			break
	var alt := DesignSession.from_selection(base, "battery", other_id)
	var a: Dictionary = MissionFlow.run(base, _opts())
	var b: Dictionary = MissionFlow.run(alt, _opts())
	var fa := String(a["result"]["build_fingerprint"])
	var fb := String(b["result"]["build_fingerprint"])
	return TestResult.new("sr6 flow: a design with another battery flies a different build than the class default", other_id != "" and fa != "" and fb != "" and fa != fb,
		"battery %s, fingerprints %s vs %s" % [other_id, fa.left(10), fb.left(10)])


static func _unknown_mission() -> TestResult:
	var r: Dictionary = MissionFlow.run(_session("five_inch"), _opts({"mission": "no_such_mission"}))
	var res: Dictionary = r["result"]
	return TestResult.new("sr6 flow: an unknown mission returns the runner's error shape, not a crash", String(res.get("ended_by", "")) == "error" and String(res.get("error", "")) != "" and not bool(res["completed"]),
		"ended_by=%s error=%s" % [res.get("ended_by", ""), String(res.get("error", "")).left(60)])
