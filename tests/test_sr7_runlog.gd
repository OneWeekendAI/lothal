class_name TestSr7Runlog
extends RefCounted
## SR7 run log. SR7.1 the run record (src/autopilot/run_record.gd): what was flown, on which versions, every output tagged, and
## it round-trips through JSON byte for byte. (SR7.2 replay and SR7.3 export cases follow in this file.) One TestResult per case.
##
## Cheap flights: five_inch hover_endurance, capacity_scale 0.15, seed 11, 3 m/s wind with 1.5 m/s gusts; the survey case reuses the
## SR5 survey flight (70 x 50 m field).
## FAIL-PROOFS (observed 2026-11-10, fix removed by a temporary edit, then restored):
## RL1 outputs lose their tag (tag blanked in _output): the whole-record, hover tag and survey tag cases FAIL (10 outputs untagged).
## RL2 JSON writer leaves integers as integers (_norm removed): the round-trip case FAILS (equal false).
## RL3 build fingerprint not copied: the whole-record case and the trail case FAIL.
## RL4 mission fields not copied (fixed stand-in): the edited-field case FAILS.
## RL5 world section dropped: the world case FAILS (section null).

const SEED := 11
static var _cache: Dictionary = {}


static func _params(extra: Dictionary = {}) -> Dictionary:
	var p := {"class_id": "five_inch", "mission": Mission.HOVER_ENDURANCE, "seed": SEED, "capacity_scale": 0.15,
		"wind_speed_mps": 3.0, "wind_from_deg": 60.0, "gust_mps": 1.5}
	for k in extra:
		p[k] = extra[k]
	return p


static func _fly(extra: Dictionary = {}) -> Array:
	var key := var_to_str(extra.keys()) + str(extra.get("fields", {}))
	if not _cache.has(key):
		var p := _params(extra)
		var r := MissionRunner.run(p)
		_cache[key] = [p, r, RunRecord.make(p, r)]
	return _cache[key]


static func run() -> Array:
	return [
		_whole(),
		_every_output_tagged(),
		_survey_outputs_tagged(),
		_round_trip(),
		_trail(),
		_edited_field(),
		_world_section(),
		_no_world(),
		_deterministic_text(),
		_real_world_room(),
	]


static func _whole() -> TestResult:
	var rec: Dictionary = _fly()[2]
	var pr := RunRecord.problems(rec)
	return TestResult.new("sr7 record: a hover run's record has every section, valid tags and non-empty versions and build fingerprint", pr.is_empty(), str(pr))


static func _every_output_tagged() -> TestResult:
	var rec: Dictionary = _fly()[2]
	var bad: Array[String] = []
	for k in rec["outputs"]:
		if String(rec["outputs"][k]["tag"]) not in RunRecord.TAGS:
			bad.append(k)
	return TestResult.new("sr7 record: every output of a hover run has a tag in {measured, published, estimated}", bad.is_empty() and rec["outputs"].size() >= 6,
		"%d outputs, untagged %s" % [rec["outputs"].size(), str(bad)])


static func _survey_outputs_tagged() -> TestResult:
	var r := TestSr5Survey._survey54(0.0, 0.0)
	var rec := RunRecord.make({"class_id": "five_inch", "mission": "survey", "seed": 11}, r)
	var bad: Array[String] = []
	for k in rec["outputs"]:
		if String(rec["outputs"][k]["tag"]) not in RunRecord.TAGS:
			bad.append(k)
	var has_all := true
	for k in ["acres_per_battery", "batteries_per_farm", "gsd_cm", "mapped_m2", "flight_time_s"]:
		has_all = has_all and rec["outputs"].has(k)
	return TestResult.new("sr7 record: a survey's outputs include acres per battery, batteries per farm, GSD and mapped area, all tagged", bad.is_empty() and has_all,
		"outputs %s, untagged %s" % [str(rec["outputs"].keys()), str(bad)])


static func _round_trip() -> TestResult:
	var rec: Dictionary = _fly()[2]
	var t1 := RunRecord.to_json(rec)
	var back := RunRecord.from_json(t1)
	var t2 := RunRecord.to_json(back)
	return TestResult.new("sr7 record: JSON text -> parse -> JSON text is byte-identical", t1 == t2 and t1.length() > 500 and back.size() == rec.size(),
		"%d bytes, equal %s" % [t1.length(), str(t1 == t2)])


static func _trail() -> TestResult:
	var rec: Dictionary = _fly()[2]
	var r: Dictionary = _fly()[1]
	var v: Dictionary = rec["versions"]
	var ok: bool = rec["build"]["fingerprint"] == r["build_fingerprint"] and String(r["build_fingerprint"]) != "" and v["app"] == LothalVersion.CURRENT \
		and String(v["rust_model"]) != "" and v["rust_model"] != "unknown" and String(v["git_sha"]) != "" and v["model"] == MissionResult.MODEL_VERSION \
		and int(v["result_schema"]) == MissionResult.SCHEMA_VERSION and String(rec["harness"]["references_sha256"]).length() == 64 and int(rec["seed"]) == SEED
	return TestResult.new("sr7 record: input trail holds the build fingerprint, app / Rust / model versions, git sha (or 'unknown'), harness references hash and the seed", ok, str(v))


static func _edited_field() -> TestResult:
	var base: Dictionary = _fly()[2]["mission"]["fields"]["reserve_pct"]
	var edited: Dictionary = _fly({"fields": {"reserve_pct": 40.0}})[2]["mission"]["fields"]["reserve_pct"]
	var inputs: Dictionary = _fly({"fields": {"reserve_pct": 40.0}})[2]["inputs"]
	return TestResult.new("sr7 record: an edited reserve is recorded as edited (value 40, tag user, default kept) and the default one is not; the override is in inputs",
		bool(edited["edited"]) and float(edited["value"]) == 40.0 and String(edited["tag"]) == "user" and float(edited["default"]) != 40.0 \
		and not bool(base["edited"]) and float(inputs["fields"]["reserve_pct"]) == 40.0,
		"edited %s, default run %s" % [str(edited), str(base)])


static func _world_section() -> TestResult:
	var w := WorldPresets.calm_test_field()
	var p := _params({"world": w, "capacity_scale": 0.15})
	var r := MissionRunner.run(p)
	var rec := RunRecord.make(p, r)
	var ok: bool = rec["world"] != null and rec["world"]["id"] == w.world_id and rec["world"]["fingerprint"] == w.fingerprint() \
		and rec["inputs"]["world"]["world_ref"] == w.world_id and rec["inputs"]["world"]["fingerprint"] == w.fingerprint()
	return TestResult.new("sr7 record: a run in a world records the world id and its fingerprint (section and inputs)", ok, str(rec["world"]))


static func _no_world() -> TestResult:
	var rec: Dictionary = _fly()[2]
	return TestResult.new("sr7 record: a run with no world has world = null (not an invented id)", rec["world"] == null and RunRecord.to_json(rec).contains("\"world\": null"), str(rec["world"]))


static func _deterministic_text() -> TestResult:
	var p := _params()
	var a := RunRecord.to_json(RunRecord.make(p, MissionRunner.run(p)))
	var b := RunRecord.to_json(_fly()[2])
	return TestResult.new("sr7 record: the same run twice gives the same record text", a == b, "%d bytes" % a.length())


static func _real_world_room() -> TestResult:
	var rec: Dictionary = _fly()[2]
	return TestResult.new("sr7 record: real_world is present and empty (room for a measured result), harness status says it was not evaluated",
		rec.has("real_world") and rec["real_world"] == null and rec["harness"]["status"] == "not evaluated", str(rec["harness"]["status"]))
