class_name RunReplay
extends RefCounted
## SR7.2: re-run a mission from its run record (RunRecord) and say whether the figures came back.
##
## replay(record) -> {status, refused, reasons, flags, identical, diffs, result, record}
##   status "identical"  - flown again, every output equal (the sim is deterministic, so equal means exactly equal, 6 decimals)
##   status "differs"    - flown again, some output moved (diffs lists name, old, new): something not in the record changed
##   status "refused"    - NOT flown, because the record cannot be reproduced here (reasons says why)
## REFUSED when: the record is not whole (RunRecord.problems), the model version differs (MissionResult.MODEL_VERSION), the result
## schema differs, the Rust model version differs, the world named in the record is not available or its fingerprint changed, the
## class is unknown or the build fingerprint changed (the parts catalog moved). A silent run under a different model would hand back
## numbers that look reproduced and are not.
## FLAGGED (flown, `flags` says so): the app version or git commit differs. They do not enter the figures by themselves; a "differs"
## status then points at them.
## `allow_version_mismatch` (default false) flies anyway for a model / schema / Rust difference and flags it, for looking at what changed.

static func replay(rec: Dictionary, allow_version_mismatch: bool = false) -> Dictionary:
	var out := {"status": "refused", "refused": true, "reasons": [], "flags": [], "identical": false, "diffs": [], "result": {}, "record": {}}
	var problems := RunRecord.problems(rec)
	if not problems.is_empty():
		out["reasons"] = ["record is not whole: " + "; ".join(problems)]
		return out
	var v: Dictionary = rec["versions"]
	var mismatches: Array[String] = []
	if String(v["model"]) != MissionResult.MODEL_VERSION:
		mismatches.append("model version %s, this build has %s" % [v["model"], MissionResult.MODEL_VERSION])
	if int(v["result_schema"]) != MissionResult.SCHEMA_VERSION:
		mismatches.append("result schema %s, this build has %d" % [str(v["result_schema"]), MissionResult.SCHEMA_VERSION])
	if String(v["rust_model"]) != RunRecord._rust_version():
		mismatches.append("Rust model %s, this build has %s" % [v["rust_model"], RunRecord._rust_version()])
	if not mismatches.is_empty():
		if allow_version_mismatch:
			for m in mismatches:
				out["flags"].append("version mismatch (flown anyway): " + m)
		else:
			out["reasons"].append_array(mismatches)
	if String(v["app"]) != LothalVersion.CURRENT:
		out["flags"].append("app version %s, this is %s" % [v["app"], LothalVersion.CURRENT])
	if String(v["git_sha"]) != RunRecord._git_sha():
		out["flags"].append("git commit %s, this is %s" % [v["git_sha"], RunRecord._git_sha()])
	var inputs: Dictionary = rec["inputs"]
	var cls := String(rec["build"]["class_id"])
	if not Mission.is_known_class(cls):
		out["reasons"].append("unknown class '%s'" % cls)
	else:
		var b := MissionRunner.make_build(cls, float(inputs.get("capacity_scale", 1.0)))
		if b.fingerprint() != String(rec["build"]["fingerprint"]):
			out["reasons"].append("build fingerprint changed (the parts catalog or the class seed moved)")
	var world: World = null
	if rec["world"] != null:
		world = find_world(String(rec["world"]["id"]))
		if world == null:
			out["reasons"].append("world '%s' is not available here" % rec["world"]["id"])
		elif world.fingerprint() != String(rec["world"]["fingerprint"]):
			out["reasons"].append("world '%s' changed (fingerprint differs)" % rec["world"]["id"])
	if not (out["reasons"] as Array).is_empty():
		return out
	var params := params_from(inputs, world)
	var r := MissionRunner.run(params)
	var new_rec := RunRecord.make(params, r)
	out["refused"] = false
	out["result"] = r
	out["record"] = new_rec
	for name in rec["outputs"]:
		var a: Dictionary = rec["outputs"][name]
		if not new_rec["outputs"].has(name):
			out["diffs"].append({"output": name, "old": a, "new": null})
			continue
		var b2: Dictionary = new_rec["outputs"][name]
		for k in ["value", "low", "high"]:
			if _differs(a.get(k), b2.get(k)):
				out["diffs"].append({"output": name, "field": k, "old": a.get(k), "new": b2.get(k)})
	out["identical"] = (out["diffs"] as Array).is_empty()
	out["status"] = "identical" if out["identical"] else "differs"
	return out


static func _differs(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a != b
	return absf(float(a) - float(b)) > 1e-6 * maxf(1.0, absf(float(a)))


## A world by id: the shipped presets first, then the user's world library.
static func find_world(id: String) -> World:
	if id in WorldPresets.IDS:
		return WorldPresets.by_id(id)
	var lib := WorldLibrary.load_dir()
	return lib.world(id) if lib.has(id) else null


## Inverse of RunRecord.plain for the keys the runner reads: polygon / path arrays back to vectors, camera preset back to a CameraParams,
## the world resolved by the caller.
static func params_from(inputs: Dictionary, world: World) -> Dictionary:
	var p := {}
	for k in inputs:
		var v: Variant = inputs[k]
		if k == "polygon":
			var poly := PackedVector2Array()
			for q in v:
				poly.append(Vector2(q[0], q[1]))
			p[k] = poly
		elif k == "path":
			var path: Array = []
			for q in v:
				path.append(Vector2(q[0], q[1]))
			p[k] = path
		elif k == "camera":
			var c := CameraParams.from_preset(String(v.get("camera_preset", ""))) if String(v.get("camera_preset", "")) != "" else CameraParams.generic_1inch()
			if c == null:
				c = CameraParams.generic_1inch()
			c.exposure_s = float(v.get("exposure_s", c.exposure_s))
			p[k] = c
		elif k == "world":
			if world != null:
				p[k] = world
		elif k == "seed" or k == "max_sorties" or k == "laps" or k == "required_photos":
			p[k] = int(v)
		else:
			p[k] = v
	return p
