class_name TestSr6Flow
extends RefCounted
## L1.1 MissionFlow: a saved design flown through MissionRunner. Short flights (capacity_scale 0.3 (the sr4 suite's short pack), hover_endurance), seed 1.
## Cases: (1) a design saved to a dict and read back flies with no opts: finite flight_time_s > 0, record has build/mission/seed.
## (2) a reserve_pct override changes the result and appears in result.params.fields. (3) a design with another battery has a different
## build_fingerprint than the class default (the saved build is flown, not the class seed). (4) an unknown mission returns the runner's
## error shape (ended_by "error", error text), no crash.
## FAIL-PROOFS observed 2026-11-10: RED A: MissionFlow drops opts.fields -> only the reserve_pct case FAILS (reserve 0 -> 0, flight_time 271.5 -> 271.5 s). RED B: MissionFlow does not pass the session build (class seed flown) -> only the saved-build case FAILS (identical fingerprints). Both GREEN after restoring (4/4). First run at capacity_scale 0.05 was not_flown (reserve exceeds usable energy), hence 0.3.
## L1.2-L1.4 FAIL-PROOFS observed 2026-11-10: RED watch: one extra rig.step() per 8-tick chunk in watch_stepped -> only the watch case FAILS (flight_time_s 271.48 vs 271.51, distance differs); merely advancing chunk-1 only shortens chunks and is invisible, so not used. RED edited: result fields' edited flag forced false -> only the edited-note case FAILS (note 'reserve 15 % (default, user)'). RED trail: seed key dropped from inputs_trail -> only the trail case FAILS (missing ["seed"]). RED margin: sign flipped -> both endurance cases FAIL (35 min gives -5.0 fails; flown 0.3x pack gives +25.5 passes). All restored, 11/11 green. The 0.3x five_inch pack flies 4.5 min.

## L1.5/L1.6 UI cases (headless, free-standing controls): picker mission count, 5 prefilled field controls, an edited field reaching the flight, env list size,
## the file bar's existing Fly it button emitting fly_pressed (DesignSpace turns that into fly_requested; unchanged), ResultsPanel text vs the dict.
## UI FAIL-PROOFS observed 2026-11-10: RED panel: set_result keeps a duplicate(true) -> only the same-dict case FAILS (12345 not shown). RED picker: options() sends the defaults not the box values -> the edit-reaches-flight case and the Watch-emits-edited-opts case FAIL (reserve 0, edited false). Both restored, 23/23 green. Fly it already existed on DesignFileBar (fly_pressed, wired to DesignSpace.fly_requested); only a test was added.

const SCALE := 0.3


static func run() -> Array:
	return [_default_flight(), _field_override(), _saved_build_flown(), _unknown_mission(),
		_watch_equal(), _edited_flagged(), _trail_present(), _presets_listed(), _saved_world_listed(), _endurance_passes(), _endurance_fails_small_pack(),
		_picker_missions(), _picker_field("height_m"), _picker_field("speed_mps"), _picker_field("front_overlap"), _picker_field("side_overlap"), _picker_field("reserve_pct"),
		_picker_edit_reaches_flight(), _picker_envs(), _picker_watch_emits(), _fly_button_emits(), _panel_text(), _panel_reads_same_dict()]


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


const SCALAR_KEYS: Array[String] = ["flight_time_s", "distance_m", "energy_wh", "reserve_left_pct", "ended_by", "sorties", "track_samples", "build_fingerprint"]


static func _watch_equal() -> TestResult:
	var s := _session("five_inch")
	var a: Dictionary = MissionFlow.run(s, _opts())["result"]
	var b: Dictionary = MissionFlow.watch_stepped(s, _opts(), 8)["result"]
	var bad: Array[String] = []
	for k in SCALAR_KEYS:
		if a[k] != b[k]:
			bad.append("%s %s vs %s" % [k, a[k], b[k]])
	return TestResult.new("sr6 flow L1.2: a flight watched in 8-tick chunks equals the headless run on every scalar field", bad.is_empty(), "differ: %s; flight_time_s=%.2f" % [str(bad), float(a["flight_time_s"])])


static func _edited_flagged() -> TestResult:
	var s := _session("five_inch")
	var r: Dictionary = MissionFlow.run(s, _opts({"fields": {"reserve_pct": 15.0}}))["result"]
	var base: Dictionary = MissionFlow.run(s, _opts())["result"]
	var f: Dictionary = r["params"]["fields"]["reserve_pct"]
	var notes := MissionFlow.figure_notes(r)
	var line := ""
	for n in notes:
		if n.begins_with("reserve"):
			line = n
	var base_line := ""
	for n in MissionFlow.figure_notes(base):
		if n.begins_with("reserve"):
			base_line = n
	var ok := bool(f["edited"]) and line.contains("edited by user") and line.contains("15 %") and line.contains("estimated") and not base_line.contains("edited by user")
	return TestResult.new("sr6 flow L1.3: a reserve override is flagged edited and the figure note says so (default and tag shown)", ok, "note='%s' base='%s'" % [line, base_line])


static func _trail_present() -> TestResult:
	var w := WorldPresets.by_id("calm_test_field")
	var r: Dictionary = MissionFlow.run(_session("five_inch"), _opts({"world": w, "seed": 7}))["result"]
	var t: Dictionary = r.get("inputs_trail", {})
	var missing: Array[String] = []
	for k in ["build_fingerprint", "class_id", "world", "seed", "versions"]:
		if not t.has(k) or t[k] == null or str(t[k]) == "":
			missing.append(k)
	var v: Dictionary = t.get("versions", {})
	for k in ["model", "app", "rust_model"]:
		if str(v.get(k, "")) == "":
			missing.append("versions." + k)
	var wd: Dictionary = t.get("world", {}) if t.get("world") is Dictionary else {}
	for k in ["id", "fingerprint"]:
		if str(wd.get(k, "")) == "":
			missing.append("world." + k)
	return TestResult.new("sr6 flow L1.3: the result carries an inputs trail with every key non-empty", missing.is_empty() and int(t.get("seed", 0)) == 7, "missing %s" % str(missing))


static func _presets_listed() -> TestResult:
	var envs := MissionFlow.environments()
	var ids: Array[String] = []
	var presets := 0
	for e in envs:
		ids.append(String(e["id"]))
		if e["kind"] == "preset":
			presets += 1
	var ok := presets == 4 and ids.has("illinois_corn_july") and ids.has("calm_test_field") and ids.has("windy_coast") and ids.has("high_altitude")
	return TestResult.new("sr6 flow L1.4: the four shipped presets are listed", ok, "ids %s" % str(ids))


static func _saved_world_listed() -> TestResult:
	var lib := WorldLibrary.new()
	var mine := World.new()
	mine.world_id = "my_back_field"
	mine.world_name = "My back field"
	lib.put(mine, false)
	lib.put(WorldPresets.by_id("windy_coast"), false)
	var envs := MissionFlow.environments(lib)
	var saved := 0
	var coast := 0
	var kind := ""
	for e in envs:
		if e["id"] == "my_back_field":
			kind = String(e["kind"])
		if e["kind"] == "saved":
			saved += 1
		if e["id"] == "windy_coast":
			coast += 1
	return TestResult.new("sr6 flow L1.4: a saved-only world is listed as saved; a saved copy of a preset is not duplicated", kind == "saved" and saved == 1 and coast == 1 and envs.size() == 5, "kind=%s saved=%d coast=%d total=%d" % [kind, saved, coast, envs.size()])


static func _endurance_passes() -> TestResult:
	var c := MissionFlow.endurance_check({"flight_time_s": 2100.0})
	return TestResult.new("sr6 flow L1.4: a 35 min result passes the 30 min check with a positive margin", c["passes"] and is_equal_approx(c["margin_min"], 5.0) and String(c["line"]).contains("+5.0 min (passes)"), str(c["line"]))


static func _endurance_fails_small_pack() -> TestResult:
	var r: Dictionary = MissionFlow.run(_session("five_inch"), _opts())["result"]
	var c := MissionFlow.endurance_check(r)
	return TestResult.new("sr6 flow L1.4: a flown 0.3x pack fails the 30 min check with a negative margin", not c["passes"] and c["margin_min"] < 0.0 and c["flight_min"] > 0.0 and String(c["line"]).contains("(fails)"), str(c["line"]))


## The suite runner builds the suites inside SceneTree._init, where no tree exists to add to (Engine.get_main_loop() is null), so
## Controls are built free-standing like the other Design Space UI tests; none of these controls needs the tree.
static func _gone(n: Node) -> void:
	n.free()


static func _picker() -> MissionPicker:
	var p := MissionPicker.new()
	p.set_session(_session("five_inch"))
	p.extra_opts = {"capacity_scale": SCALE}
	return p


static func _picker_missions() -> TestResult:
	var p := _picker()
	var n := p.mission_list.item_count
	_gone(p)
	return TestResult.new("sr6 flow L1.5: the picker lists every mission but the test pack", n == Mission.IDS.size() - 1 and n == 5, "items %d of %d ids" % [n, Mission.IDS.size()])


static func _picker_field(key: String) -> TestResult:
	var p := _picker()
	var d: Dictionary = Mission.defaults_for("five_inch", p.mission_id())["fields"][key]
	var box: SpinBox = p.field_boxes.get(key)
	var tag := (p.tag_labels[key] as Label).text if box != null else ""
	var ok: bool = box != null and is_equal_approx(box.value, float(d["value"])) and tag == String(d["tag"])
	var got := box.value if box != null else -1.0
	_gone(p)
	return TestResult.new("sr6 flow L1.5: field %s is present, prefilled with the default and shows its tag" % key, ok, "value %s default %s tag '%s'" % [got, d["value"], tag])


static func _picker_edit_reaches_flight() -> TestResult:
	var p := _picker()
	(p.field_boxes["reserve_pct"] as SpinBox).value = 15.0
	var r := p.run_headless()
	var f: Dictionary = r["result"]["params"]["fields"]["reserve_pct"] if not r.is_empty() else {}
	var ok: bool = not f.is_empty() and float(f["value"]) == 15.0 and bool(f["edited"]) and p.results.text().contains("edited by user")
	_gone(p)
	return TestResult.new("sr6 flow L1.5: editing a field then Headless flies the edited value and the result slot says so", ok, str(f))


static func _picker_envs() -> TestResult:
	var p := _picker()
	var n := p.env_option.item_count
	_gone(p)
	return TestResult.new("sr6 flow L1.5: the environment list is MissionFlow.environments()", n == MissionFlow.environments().size() and n >= 4, "items %d" % n)


static func _picker_watch_emits() -> TestResult:
	var p := _picker()
	var got := []
	p.watch_requested.connect(func(o: Dictionary): got.append(o))
	(p.field_boxes["speed_mps"] as SpinBox).value = 9.0
	p.watch_button.pressed.emit()
	var ok := got.size() == 1 and float(got[0]["fields"]["speed_mps"]) == 9.0 and p.last.is_empty()
	_gone(p)
	return TestResult.new("sr6 flow L1.5: Watch only emits watch_requested with the edited opts and flies nothing", ok, str(got.size()))


static func _fly_button_emits() -> TestResult:
	var bar := DesignFileBar.new()
	var n := [0]
	bar.fly_pressed.connect(func(): n[0] += 1)
	var has := bar.fly_button != null and bar.fly_button.text == "Fly it"
	bar.fly_button.pressed.emit()
	bar.free()
	return TestResult.new("sr6 flow L1.5: the file bar has a Fly it button and it emits fly_pressed", has and n[0] == 1, "emits %d" % n[0])


static func _flown(seed_n: int) -> Dictionary:
	return MissionFlow.run(_session("five_inch"), _opts({"seed": seed_n}))["result"]


static func _panel_text() -> TestResult:
	var r := _flown(7)
	var panel := ResultsPanel.new()
	panel.set_result(r)
	var t := panel.text()
	var missing: Array[String] = []
	for k in r["figures"]:
		if not t.contains(k) or not t.contains("[%s]" % r["figures"][k]["tag"]) or not t.contains(String(r["figures"][k]["unit"])):
			missing.append(k)
	var ok: bool = missing.is_empty() and r["figures"].size() > 0 and t.contains("seed 7") and t.contains(MissionFlow.endurance_check(r)["line"])
	_gone(panel)
	return TestResult.new("sr6 flow L1.6: the panel shows every figure with unit and tag, the endurance line and the trail seed", ok, "missing %s" % str(missing))


static func _panel_reads_same_dict() -> TestResult:
	var r := _flown(7)
	var panel := ResultsPanel.new()
	panel.set_result(r)
	var before := panel.text()
	r["figures"]["flight_time_s"]["value"] = 12345.0
	panel.render()
	var ok := not before.contains("12345.00") and panel.text().contains("12345.00")
	var shown := panel.text().left(120)
	_gone(panel)
	return TestResult.new("sr6 flow L1.6: the panel reads the dict it was given (a changed value shows after render)", ok, shown)
