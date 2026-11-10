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
## SR7.2 replay (observed 2026-11-10): RP1 version checks removed (model, schema, Rust): 4 FAIL (the three refusals and the allow-mismatch flag; flown silently, status identical).
## RP2 build fingerprint check removed: the build refusal FAILS. RP3 world fingerprint check removed: the world-changed refusal FAILS.
## RP4 compare never reports a difference: the tampered-output and edited-input cases FAIL (status identical, 0 diffs). RP5 world not passed to the run: the world replay FAILS (status differs).

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
		_replay_identical(),
		_replay_world_identical(),
		_refuse_model(),
		_refuse_schema(),
		_refuse_rust(),
		_refuse_build(),
		_refuse_world_changed(),
		_refuse_world_missing(),
		_refuse_incomplete(),
		_flag_app_version(),
		_allow_mismatch_flags(),
		_tampered_output_differs(),
		_edited_input_differs(),
		_csv_every_row_tagged(),
		_csv_row_count(),
		_csv_values_match(),
		_csv_edited_note(),
		_csv_quoting_round_trip(),
		_csv_trail_every_row(),
		_json_file_matches(),
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


# ---------------------------------------------------------------- SR7.2 replay
## A record goes through its JSON text first (what a saved file is), then is edited as a plain dictionary.
static func _saved(extra: Dictionary = {}) -> Dictionary:
	return RunRecord.from_json(RunRecord.to_json(_fly(extra)[2]))


static func _replay_identical() -> TestResult:
	var rp := RunReplay.replay(_saved())
	return TestResult.new("sr7 replay: a saved hover record flown again gives identical outputs (no diffs, no flags)",
		rp["status"] == "identical" and not rp["refused"] and (rp["diffs"] as Array).is_empty() and (rp["flags"] as Array).is_empty(),
		"status %s, diffs %s, flags %s" % [rp["status"], str(rp["diffs"]), str(rp["flags"])])


static func _replay_world_identical() -> TestResult:
	var w := WorldPresets.by_id("calm_test_field")
	var p := _params({"world": w})
	var rec := RunRecord.from_json(RunRecord.to_json(RunRecord.make(p, MissionRunner.run(p))))
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: a run in the shipped calm_test_field world replays identically (the world is found by id and its fingerprint checked)",
		rp["status"] == "identical" and rec["world"] != null, "status %s, reasons %s, diffs %s" % [rp["status"], str(rp["reasons"]), str(rp["diffs"])])


static func _refused(rp: Dictionary, word: String) -> bool:
	return rp["status"] == "refused" and rp["refused"] and (rp["result"] as Dictionary).is_empty() and "\n".join(rp["reasons"]).contains(word)


static func _refuse_model() -> TestResult:
	var rec := _saved()
	rec["versions"]["model"] = "sr4-1"
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: an edited model version is REFUSED (nothing flown, the reason names the model)", _refused(rp, "model version"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_schema() -> TestResult:
	var rec := _saved()
	rec["versions"]["result_schema"] = 99
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: an edited result schema is REFUSED", _refused(rp, "schema"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_rust() -> TestResult:
	var rec := _saved()
	rec["versions"]["rust_model"] = "0.0.1"
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: an edited Rust model version is REFUSED", _refused(rp, "Rust model"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_build() -> TestResult:
	var rec := _saved()
	rec["build"]["fingerprint"] = "deadbeef"
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: a build fingerprint that no longer matches the class is REFUSED", _refused(rp, "build fingerprint"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_world_changed() -> TestResult:
	var w := WorldPresets.by_id("calm_test_field")
	var p := _params({"world": w})
	var rec := RunRecord.from_json(RunRecord.to_json(RunRecord.make(p, MissionRunner.run(p))))
	rec["world"]["fingerprint"] = "changed"
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: a world whose fingerprint changed is REFUSED", _refused(rp, "changed"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_world_missing() -> TestResult:
	var w := WorldPresets.by_id("calm_test_field")
	var p := _params({"world": w})
	var rec := RunRecord.from_json(RunRecord.to_json(RunRecord.make(p, MissionRunner.run(p))))
	rec["world"]["id"] = "no_such_world_anywhere"
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: a world that is not available here is REFUSED", _refused(rp, "not available"), str(rp["reasons"]) + " / status " + str(rp["status"]))


static func _refuse_incomplete() -> TestResult:
	var rec := _saved()
	rec.erase("versions")
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: a record without its versions section is REFUSED as not whole", _refused(rp, "not whole"), str(rp["reasons"]))


static func _flag_app_version() -> TestResult:
	var rec := _saved()
	rec["versions"]["app"] = "0.0.1"
	var rp := RunReplay.replay(rec)
	var flagged := "\n".join(rp["flags"]).contains("app version")
	return TestResult.new("sr7 replay: a different app version is flown and FLAGGED (not refused); the figures still match", flagged and rp["status"] == "identical", str(rp["flags"]) + " / " + str(rp["status"]))


static func _allow_mismatch_flags() -> TestResult:
	var rec := _saved()
	rec["versions"]["model"] = "sr4-1"
	var rp := RunReplay.replay(rec, true)
	return TestResult.new("sr7 replay: with allow_version_mismatch a model difference is flown and flagged 'version mismatch'",
		not rp["refused"] and "\n".join(rp["flags"]).contains("version mismatch"), str(rp["flags"]) + " / " + str(rp["status"]))


static func _tampered_output_differs() -> TestResult:
	var rec := _saved()
	rec["outputs"]["flight_time_s"]["value"] = float(rec["outputs"]["flight_time_s"]["value"]) + 5.0
	var rp := RunReplay.replay(rec)
	var named := false
	for d in rp["diffs"]:
		named = named or d["output"] == "flight_time_s"
	return TestResult.new("sr7 replay: a record whose stored flight time was altered by 5 s replays as 'differs' and names flight_time_s", rp["status"] == "differs" and named, str(rp["diffs"]))


static func _edited_input_differs() -> TestResult:
	var rec := _saved()
	rec["inputs"]["wind_speed_mps"] = 9.0
	var rp := RunReplay.replay(rec)
	return TestResult.new("sr7 replay: an input changed behind the record's back (wind 3 -> 9 m/s) replays as 'differs'", rp["status"] == "differs" and (rp["diffs"] as Array).size() > 0,
		"status %s, %d diffs" % [rp["status"], (rp["diffs"] as Array).size()])


# ---------------------------------------------------------------- SR7.3 export
## CSV is parsed back with FileAccess.get_csv_line (a real RFC 4180 reader), not by splitting on commas.
## FAIL-PROOFS (observed 2026-11-10): CS1 output tag written empty: the tag case FAILS (15 of 21 rows). CS2 quoting removed: the quoting and trail cases FAIL.
## CS3 trail column dropped from output rows: the trail case FAILS (15 rows). CS4 edited note dropped: the edited case FAILS. CS5 save_json writing other text: the json file case FAILS.
const CSV_PATH := "user://sr7_export_test.csv"
const JSON_PATH := "user://sr7_export_test.json"


static func _read_csv(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	var rows: Array = []
	if f == null:
		return rows
	while not f.eof_reached():
		var line := f.get_csv_line()
		if line.size() > 1 or (line.size() == 1 and line[0] != ""):
			rows.append(line)
	return rows


static func _csv_rows(rec: Dictionary) -> Array:
	RunRecord.save_csv(rec, CSV_PATH)
	return _read_csv(CSV_PATH)


static func _survey_record() -> Dictionary:
	return RunRecord.make({"class_id": "five_inch", "mission": "survey", "seed": 11}, TestSr5Survey._survey54(0.0, 0.0))


static func _csv_every_row_tagged() -> TestResult:
	var rows := _csv_rows(_survey_record())
	var bad := 0
	for i in range(1, rows.size()):
		if String(rows[i][6]) not in RunRecord.TAGS:
			bad += 1
	return TestResult.new("sr7 csv: every data row of a survey export has a tag in {measured, published, estimated}", bad == 0 and rows.size() > 12 and rows[0] == PackedStringArray(RunRecord.CSV_HEADER),
		"%d rows, %d bad tags, header %s" % [rows.size(), bad, str(rows[0] if rows.size() > 0 else [])])


static func _csv_row_count() -> TestResult:
	var rec := _survey_record()
	var rows := _csv_rows(rec)
	var want := 1 + (rec["mission"]["fields"] as Dictionary).size() + (rec["outputs"] as Dictionary).size()
	return TestResult.new("sr7 csv: one header + one row per input field + one row per output (no row lost to quoting)", rows.size() == want, "%d rows, expected %d" % [rows.size(), want])


static func _csv_values_match() -> TestResult:
	var rec := _survey_record()
	var rows := _csv_rows(rec)
	var ok := false
	var detail := ""
	for r in rows:
		if r[0] == "output" and r[1] == "acres_per_battery":
			var o: Dictionary = rec["outputs"]["acres_per_battery"]
			ok = absf(float(r[2]) - float(o["value"])) < 1e-5 and absf(float(r[3]) - float(o["low"])) < 1e-5 and absf(float(r[4]) - float(o["high"])) < 1e-5 and r[5] == "acres/battery"
			detail = str(r)
	return TestResult.new("sr7 csv: the acres_per_battery row carries the record's value, low, high and unit", ok, detail)


static func _csv_edited_note() -> TestResult:
	var rec: Dictionary = _fly({"fields": {"reserve_pct": 40.0}})[2]
	var rows := _csv_rows(rec)
	var ok := false
	var detail := ""
	for r in rows:
		if r[0] == "input" and r[1] == "reserve_pct":
			ok = r[7].contains("edited by user") and float(r[2]) == 40.0 and r[6] in RunRecord.TAGS
			detail = str(r)
	return TestResult.new("sr7 csv: an edited reserve is exported as an input row with value 40, the default's tag and 'edited by user' in the note", ok, detail)


static func _csv_quoting_round_trip() -> TestResult:
	var rec := _survey_record()
	var want := String(rec["outputs"]["acres_per_battery"]["range"])
	var got := ""
	for r in _csv_rows(rec):
		if r[0] == "output" and r[1] == "acres_per_battery":
			got = r[7]
	return TestResult.new("sr7 csv: a range text holding commas survives quoting and parsing unchanged", want.contains(",") and got == want, "want [%s] got [%s]" % [want, got])


static func _csv_trail_every_row() -> TestResult:
	var rec := _survey_record()
	var want := "%s | %s | seed %d | world none" % [rec["build"]["fingerprint"], rec["versions"]["model"], int(rec["seed"])]
	var rows := _csv_rows(rec)
	var bad := 0
	for i in range(1, rows.size()):
		if rows[i][8] != want:
			bad += 1
	return TestResult.new("sr7 csv: every row repeats the trail (build fingerprint | model | seed | world)", bad == 0 and String(rec["build"]["fingerprint"]) != "", "%d rows differ; want [%s]" % [bad, want])


static func _json_file_matches() -> TestResult:
	var rec: Dictionary = _fly()[2]
	var ok := RunRecord.save_json(rec, JSON_PATH)
	var text := FileAccess.get_file_as_string(JSON_PATH)
	return TestResult.new("sr7 json export: the file holds exactly the record text and parses back to a whole record", ok and text == RunRecord.to_json(rec) and RunRecord.problems(RunRecord.from_json(text)).is_empty(),
		"%d bytes" % text.length())
