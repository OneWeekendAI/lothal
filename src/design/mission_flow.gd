class_name MissionFlow
extends RefCounted
## L1.1 design -> mission, no UI. MissionFlow.run(session, opts) flies a saved design (a DesignSession, as
## DesignFile.load_file(...)["session"] returns) through MissionRunner headless: the Build is session.build(catalog), the class is
## session.drone_class, the field defaults are Mission.defaults_for for that class. The design's own parts are flown, not the class seed.
## opts: mission (default "hover_endurance"), seed (default 1), fields overrides, and any other MissionRunner param (world,
## wind_speed_mps, wind_from_deg, gust_mps, capacity_scale, hover_s, ...), passed through unchanged.
## Returns {"result", "record", "params"}. A refusal (unknown mission, design that does not build) returns the runner's error-shaped result.

const DEFAULT_MISSION := "hover_endurance"


## L1.2 watch_stepped: the same flight stepped in chunks of chunk_ticks (begin / advance / is_done / finish, as Main.watch_mission
## does); equal to run() field by field for the same session, opts and seed.
## L1.3 the result carries "inputs_trail" (what was flown: build fingerprint, class, world id+fingerprint or null, seed, versions);
## figure_notes(result) lists each mission field with its value, whether the user edited it, the default and the default's tag.
## L1.4 environments() lists the worlds a user can pick; endurance_check() judges a flight against a target time.

const UNITS := {"pct": "%", "m": "m", "mps": "m/s", "overlap": "%"}
const TARGET_MIN := 30.0


static func _prepare(session: DesignSession, opts: Dictionary) -> Dictionary:
	var params: Dictionary = opts.duplicate()
	params["mission"] = String(opts.get("mission", DEFAULT_MISSION))
	params["seed"] = int(opts.get("seed", 1))
	params["class_id"] = session.drone_class
	var build := session.build(PartsCatalog.load_default())
	if build != null:
		params["build"] = build
	return params


static func _package(params: Dictionary, result: Dictionary) -> Dictionary:
	var rec := RunRecord.make(params, result)
	result["inputs_trail"] = {"build_fingerprint": rec["build"]["fingerprint"], "class_id": rec["build"]["class_id"],
		"world": _world_trail(rec["world"]),
		"seed": rec["seed"], "versions": {"model": rec["versions"]["model"], "app": rec["versions"]["app"], "rust_model": rec["versions"]["rust_model"]}}
	return {"result": result, "record": rec, "params": params}


static func _world_trail(w: Variant) -> Variant:
	if w == null:
		return null
	return {"id": (w as Dictionary)["id"], "fingerprint": (w as Dictionary)["fingerprint"]}


static func run(session: DesignSession, opts: Dictionary = {}) -> Dictionary:
	var params := _prepare(session, opts)
	var result: Dictionary
	if not params.has("build"):
		result = MissionRunner.refuse(params, "design does not build: a required part is missing")
	else:
		result = MissionRunner.run(params)
	return _package(params, result)


static func watch_stepped(session: DesignSession, opts: Dictionary, chunk_ticks: int) -> Dictionary:
	var params := _prepare(session, opts)
	var result: Dictionary
	if not params.has("build"):
		result = MissionRunner.refuse(params, "design does not build: a required part is missing")
	else:
		var runner := MissionRunner.new()
		if runner.begin(params):
			while not runner.is_done():
				runner.advance(maxi(1, chunk_ticks))
		result = runner.finish()
	return _package(params, result)


static func figure_notes(result: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var fields: Dictionary = result.get("params", {}).get("fields", {})
	for k in fields:
		var f: Dictionary = fields[k]
		var parts := String(k).rsplit("_", true, 1)
		var label := String(k)
		var unit := ""
		if parts.size() == 2 and UNITS.has(parts[1]) and parts[1] != "overlap":
			label = parts[0]
			unit = String(UNITS[parts[1]])
		elif String(k).ends_with("overlap"):
			unit = "%"
		if bool(f.get("edited", false)):
			out.append("%s %s %s (edited by user, default %s %s, %s)" % [label, _n(float(f["value"])), unit, _n(float(f["default"])), unit, f["default_tag"]])
		else:
			out.append("%s %s %s (default, %s)" % [label, _n(float(f["value"])), unit, f["tag"]])
	return out


static func _n(v: float) -> String:
	if is_equal_approx(v, round(v)):
		return "%d" % int(v)
	return "%.1f" % v


## Worlds to pick from: the shipped presets, then any saved world of the library not already listed by id.
static func environments(lib: WorldLibrary = null) -> Array:
	var out: Array = []
	var seen := {}
	for w in WorldPresets.all():
		seen[w.world_id] = true
		out.append({"id": w.world_id, "name": w.world_name, "kind": "preset", "tag": w.location_tag()})
	if lib != null:
		for id in lib.ids():
			if seen.has(id):
				continue
			seen[id] = true
			var w := lib.world(id)
			out.append({"id": id, "name": w.world_name, "kind": "saved", "tag": w.location_tag()})
	return out


static func endurance_check(result: Dictionary, target_min: float = TARGET_MIN) -> Dictionary:
	var flight_min := float(result.get("flight_time_s", 0.0)) / 60.0
	var margin := flight_min - target_min
	var passes := margin >= 0.0
	return {"target_min": target_min, "flight_min": flight_min, "margin_min": margin, "passes": passes,
		"line": "%.1f min vs %s min target: %+.1f min (%s)" % [flight_min, _n(target_min), margin, "passes" if passes else "fails"]}
