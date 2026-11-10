class_name RunRecord
extends RefCounted
## SR7.1: the run record. One flat, self-describing document per mission run: what was flown (build, world, mission and which
## fields were edited, seed), on which versions of the model and data, and every output with its tag. Built from the params the
## caller gave and the MissionResult the run returned; it does not fly anything.
##
## Sections: kind, record_version, build {class_id, fingerprint}, world {id, fingerprint, name} or null, mission {name, fields (value /
## default / edited / tag per field)}, seed, conditions, inputs (the plain-data form of the params; replay reads this, SR7.2),
## versions {model, result_schema, app, rust_model, git_sha, camera_preset}, harness {status, references_sha256, field_flags}, outputs
## {name -> {value, low, high, tag, unit, range}}, status {ended_by, completed, warnings}, real_world (null: room for a measured result beside
## the predicted one, filled by the user later, never by the sim).
## Every output carries a tag in {measured, published, estimated}. Nothing in the record is a wall-clock time, so the same run gives the
## same text (the sim's own determinism, see MissionRunner).
##
## harness.status is "not evaluated": the sim-reality harness takes minutes and is not run per mission. The record names the references
## file it would be judged against (sha256) so a later reader can tell whether the references moved.

const VERSION := 1
const KIND := "lothal.run_record"
const TAGS: Array[String] = ["measured", "published", "estimated"]
const OUTPUT_KEYS: Array[String] = ["acres_per_battery", "batteries_per_farm"]


static func make(params: Dictionary, result: Dictionary) -> Dictionary:
	var world: Variant = null
	if result.has("world"):
		var w: Dictionary = result["world"]
		world = {"id": w["id"], "fingerprint": w["fingerprint"], "name": w["name"], "version": w["version"]}
	var camera_preset := ""
	var cam: Variant = params.get("camera")
	if cam is CameraParams:
		camera_preset = (cam as CameraParams).preset_id
	var rec := {
		"kind": KIND, "record_version": VERSION,
		"build": {"class_id": result.get("class_id", ""), "fingerprint": result.get("build_fingerprint", "")},
		"world": world,
		"mission": {"name": result.get("mission", ""), "fields": result.get("params", {}).get("fields", {})},
		"seed": result.get("seed", 0),
		"conditions": result.get("conditions", {}),
		"inputs": plain(params),
		"versions": {"model": result.get("versions", {}).get("model", ""), "result_schema": result.get("schema_version", 0),
			"app": LothalVersion.CURRENT, "rust_model": _rust_version(), "git_sha": _git_sha(), "camera_preset": camera_preset},
		"harness": {"status": "not evaluated", "references_sha256": _references_sha(), "field_flags": _field_flags()},
		"outputs": outputs_of(result),
		"status": {"ended_by": result.get("ended_by", ""), "completed": result.get("completed", false), "warnings": result.get("warnings", [])},
		"real_world": null,
	}
	return rec


## Every number the result reports as a figure, plus the economics blocks, each as {value, low, high, tag, unit, range}.
static func outputs_of(result: Dictionary) -> Dictionary:
	var out := {}
	for k in result.get("figures", {}):
		out[k] = _output(result["figures"][k])
	for k in OUTPUT_KEYS:
		if result.has(k):
			out[k] = _output(result[k])
	return out


static func _output(f: Dictionary) -> Dictionary:
	return {"value": f.get("value"), "low": f.get("low"), "high": f.get("high"), "tag": String(f.get("tag", "")),
		"unit": String(f.get("unit", "")), "range": String(f.get("range", ""))}


## Plain-data form of a params dictionary: numbers, strings, bools, arrays, dictionaries. Vectors become arrays, a camera becomes its
## preset id and exposure, a world its id and fingerprint; anything else is dropped (a Callable cannot be replayed).
static func plain(v: Variant) -> Variant:
	if v is CameraParams:
		var c := v as CameraParams
		return {"camera_preset": c.preset_id, "exposure_s": c.exposure_s}
	if v is World:
		var w := v as World
		return {"world_ref": w.world_id, "fingerprint": w.fingerprint()}
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR2:
			return [v.x, v.y]
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(plain(x))
			return a
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				var p: Variant = plain(v[k])
				if p != null or v[k] == null:
					d[String(k)] = p
			return d
	return null


## Text form: sorted keys, floats snapped to 6 decimals, whole numbers written as floats (so text -> parse -> text is byte-identical:
## the JSON parser returns every number as a float), NaN / INF -> null.
static func to_json(rec: Dictionary) -> String:
	return JSON.stringify(_norm(MissionResult._clean(rec)), "  ", true)


static func _norm(v: Variant) -> Variant:
	match typeof(v):
		TYPE_INT:
			return float(v)
		TYPE_DICTIONARY:
			var d := {}
			for k in v:
				d[k] = _norm(v[k])
			return d
		TYPE_ARRAY:
			var a := []
			for x in v:
				a.append(_norm(x))
			return a
	return v


static func from_json(text: String) -> Dictionary:
	var d: Variant = JSON.parse_string(text)
	return d if d is Dictionary else {}


## Problems with a record: [] when it is whole. Used by tests and by replay before it trusts a file.
static func problems(rec: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for k in ["kind", "record_version", "build", "world", "mission", "seed", "inputs", "versions", "harness", "outputs", "status", "real_world"]:
		if not rec.has(k):
			out.append("missing " + k)
	if String(rec.get("kind", "")) != KIND:
		out.append("not a run record")
	for name in rec.get("outputs", {}):
		if String(rec["outputs"][name].get("tag", "")) not in TAGS:
			out.append("output %s has no valid tag" % name)
	for k in ["model", "app", "rust_model"]:
		if String(rec.get("versions", {}).get(k, "")) == "":
			out.append("version %s is empty" % k)
	if String(rec.get("build", {}).get("fingerprint", "")) == "":
		out.append("build fingerprint is empty")
	return out


static func _rust_version() -> String:
	var text := FileAccess.get_file_as_string("res://rust/Cargo.toml")
	for line in text.split("\n"):
		if line.begins_with("version"):
			return line.get_slice("\"", 1)
	return "unknown"


static func _git_sha() -> String:
	var out: Array = []
	var code := OS.execute("git", ["-C", ProjectSettings.globalize_path("res://"), "rev-parse", "--short", "HEAD"], out)
	var sha := String(out[0]).strip_edges() if code == 0 and out.size() > 0 else ""
	return sha if sha != "" else "unknown"


static func _references_sha() -> String:
	var t := FileAccess.get_file_as_string("res://tests/sim_reality/references.json")
	return t.sha256_text() if t != "" else "unknown"


## The field-physics flags in force for a mission run: the defaults of Build.apply_field_physics, which FlightRig uses (it passes no options). Update this if that default list changes.
static func _field_flags() -> String:
	return JSON.stringify({"avionics": true, "battery": true, "esc": true, "ground_effect": false, "payload": true, "thermal": true})
