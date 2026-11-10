class_name MissionFlow
extends RefCounted
## L1.1 design -> mission, no UI. MissionFlow.run(session, opts) flies a saved design (a DesignSession, as
## DesignFile.load_file(...)["session"] returns) through MissionRunner headless: the Build is session.build(catalog), the class is
## session.drone_class, the field defaults are Mission.defaults_for for that class. The design's own parts are flown, not the class seed.
## opts: mission (default "hover_endurance"), seed (default 1), fields overrides, and any other MissionRunner param (world,
## wind_speed_mps, wind_from_deg, gust_mps, capacity_scale, hover_s, ...), passed through unchanged.
## Returns {"result", "record", "params"}. A refusal (unknown mission, design that does not build) returns the runner's error-shaped result.

const DEFAULT_MISSION := "hover_endurance"


static func run(session: DesignSession, opts: Dictionary = {}) -> Dictionary:
	var params: Dictionary = opts.duplicate()
	params["mission"] = String(opts.get("mission", DEFAULT_MISSION))
	params["seed"] = int(opts.get("seed", 1))
	params["class_id"] = session.drone_class
	var build := session.build(PartsCatalog.load_default())
	if build != null:
		params["build"] = build
	var result: Dictionary
	if build == null:
		result = MissionRunner.refuse(params, "design does not build: a required part is missing")
	else:
		result = MissionRunner.run(params)
	return {"result": result, "record": RunRecord.make(params, result), "params": params}
