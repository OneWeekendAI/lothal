class_name Mission
extends RefCounted
## SR4 ready-made missions: ids and the per-class DEFAULTS table. Every editable field is
## {value, tag, note}: tag is 'estimated' | 'published' | 'measured' (rule 3/5 of the plan: a guess gets a
## label and a field the user can change). Nothing here is measured or published yet, so every tag is
## 'estimated' and the note says how the number was chosen.
##
## Editable fields: height_m, speed_mps, front_overlap, side_overlap, reserve_pct.
## Extras (not user fields, but labelled the same way): loop_side_m, survey field, hover_s, laps, max_sorties,
## climb / descent rate.
##
## HOW THE DEFAULTS WERE CHOSEN (no measurement behind any of them)
##  * Cruise speed and height: the numbers named in the SR4 brief (5 inch 12 m/s at 20 m reserve 25 %,
##    seven_lr 12 m/s at 30 m reserve 20 %, cinelifter 8 m/s at 30 m reserve 25 %, mavic_3m mapper 60 m, 8 m/s,
##    overlap 75/65, reserve 25 %).
##  * Any other class: speed = 40 % of the build's own top speed (clamped 3..15 m/s), height 20 m, reserve 30 %
##    (conservative: higher than every named class).
##  * Survey height and field: the camera's minimum shot interval caps the survey speed (spacing along the
##    track / min interval), so the FPV classes survey SLOWLY. The survey SPEED default is min(cruise speed,
##    0.95 x that cap). The field is sized so ONE pack flies only part of it (the battery swap then matters):
##    5 inch 120 x 80 m at 25 m, seven_lr 200 x 120 m at 40 m, cinelifter 160 x 100 m at 40 m, mavic 700 x 400 m
##    at 60 m, other classes 80 x 60 m at 20 m.
##  * Front / side overlap 75 / 65 % for every class (a mapping convention, estimated).
##  * Hover endurance reserve 0 %: the mission is "hold until cutoff" by definition; raise it to land with a reserve.

const HOVER_ENDURANCE := "hover_endurance"
const CRUISE_LOOP := "cruise_loop"
const RANGE_TEST := "range_test"
const SURVEY := "survey"
const FOLLOW_PATH := "follow_path"
const TEST_PACK := "test_pack"
const IDS: Array[String] = [HOVER_ENDURANCE, CRUISE_LOOP, RANGE_TEST, SURVEY, FOLLOW_PATH, TEST_PACK]
const FIELDS: Array[String] = ["height_m", "speed_mps", "front_overlap", "side_overlap", "reserve_pct"]

const CLIMB_RATE_MPS := 2.5
const DESCENT_RATE_MPS := 1.5
const DEFAULT_HOVER_S := 60.0
const DEFAULT_LAPS := 2
const DEFAULT_SURVEY_SORTIES := 4

## per class: cruise height / speed / reserve, survey height and field (w x h metres). All 'estimated'.
const TABLE := {
	"five_inch": {"height_m": 20.0, "speed_mps": 12.0, "reserve_pct": 25.0, "survey_height_m": 25.0, "survey_field_m": Vector2(120, 80)},
	"seven_lr": {"height_m": 30.0, "speed_mps": 12.0, "reserve_pct": 20.0, "survey_height_m": 40.0, "survey_field_m": Vector2(200, 120)},
	"cinelifter": {"height_m": 30.0, "speed_mps": 8.0, "reserve_pct": 25.0, "survey_height_m": 40.0, "survey_field_m": Vector2(160, 100)},
	"mavic_3m": {"height_m": 60.0, "speed_mps": 8.0, "reserve_pct": 25.0, "survey_height_m": 60.0, "survey_field_m": Vector2(700, 400)},
}


static func is_mission(id: String) -> bool:
	return id in IDS


## True for a Design Space class id or a tests/sim_reality/references.json id.
static func is_known_class(class_id: String) -> bool:
	return DroneClass.is_available(class_id) or not SimRealityHarness.find_reference(class_id).is_empty()


static func _f(value: float, note: String) -> Dictionary:
	return {"value": value, "tag": "estimated", "note": note, "edited": false}


## SR4.2: the defaults table resolved against user overrides (name -> number). Returns, for every name in FIELDS,
## {value, default, edited, tag, default_tag, note}: edited is true only when the override differs from the default;
## an edited field's tag is 'user' (the value is the user's, not an estimate). The mission runner reports exactly these.
static func resolve_fields(defaults: Dictionary, overrides: Dictionary) -> Dictionary:
	var out := {}
	for k in FIELDS:
		var d: Dictionary = defaults["fields"][k]
		var v := float(overrides.get(k, d["value"]))
		out[k] = MissionResult.param(v, d, overrides.has(k) and not is_equal_approx(v, float(d["value"])))
	return out


## Defaults for a class and mission. {ok:false, error:"..."} for an unknown class or mission. `build`
## (optional) is only used to derive defaults for a class without a table entry.
static func defaults_for(class_id: String, mission_id: String, build: Build = null) -> Dictionary:
	if not is_mission(mission_id):
		return {"ok": false, "error": "unknown mission '%s' (known: %s)" % [mission_id, ", ".join(IDS)]}
	if not is_known_class(class_id):
		return {"ok": false, "error": "unknown class '%s' (not a Design Space class id nor a references.json id)" % class_id}
	var row: Dictionary
	var src: String
	if TABLE.has(class_id):
		row = TABLE[class_id]
		src = "per-class default from the SR4 brief"
	else:
		var top_mps := 12.0
		if build != null:
			top_mps = build.top_speed_kmh() / 3.6
		var v := clampf(0.4 * top_mps, 3.0, 15.0)
		row = {"height_m": 20.0, "speed_mps": snappedf(v, 0.5), "reserve_pct": 30.0, "survey_height_m": 20.0,
			"survey_field_m": Vector2(80, 60)}
		src = "derived: 40%% of the build's top speed (%.1f m/s), clamped 3..15, conservative reserve" % top_mps
	var fields := {
		"height_m": _f(row["height_m"], "%s (estimated)" % src),
		"speed_mps": _f(row["speed_mps"], "%s (estimated)" % src),
		"front_overlap": _f(0.75, "mapping convention 75 %% front overlap (estimated)"),
		"side_overlap": _f(0.65, "mapping convention 65 %% side overlap (estimated)"),
		"reserve_pct": _f(row["reserve_pct"], "%s (estimated)" % src),
	}
	var cam := CameraParams.generic_1inch()
	var extras := {
		"loop_side_m": _f(maxf(80.0, 12.0 * float(row["speed_mps"])), "square loop side = 12 s of cruise, at least 80 m (estimated)"),
		"survey_field_m": row["survey_field_m"],
		"hover_s": _f(DEFAULT_HOVER_S, "standard pack hover part: fixed 60 s (estimated)"),
		"laps": _f(float(DEFAULT_LAPS), "standard pack cruise part: 2 laps (estimated)"),
		"climb_rate_mps": _f(CLIMB_RATE_MPS, "stated take-off climb rate (estimated)"),
		"descent_rate_mps": _f(DESCENT_RATE_MPS, "stated landing descent rate (estimated)"),
		"max_sorties": _f(float(DEFAULT_SURVEY_SORTIES) if mission_id in [SURVEY, TEST_PACK] else 1.0,
			"battery swaps allowed (survey only; swap time is not counted in flight time)"),
		"survey_height_m": _f(row["survey_height_m"], "survey height for this class (estimated)"),
	}
	if mission_id == HOVER_ENDURANCE:
		fields["reserve_pct"] = _f(0.0, "hover endurance holds until battery cutoff by definition, so no reserve (estimated); raise it to land with a reserve")
	if mission_id in [SURVEY, TEST_PACK]:
		var h: float = row["survey_height_m"]
		var sp := fp_survey_speed(cam, h, 0.75, float(row["speed_mps"]))
		extras["survey_speed_mps"] = _f(sp, "min(cruise speed, 0.95 x camera-interval cap %.2f m/s) (estimated)" % (cam.footprint_m(h).y * 0.25 / cam.min_shot_interval_s))
		if mission_id == SURVEY:
			fields["height_m"] = _f(h, "survey height for this class (estimated)")
			fields["speed_mps"] = extras["survey_speed_mps"].duplicate()
	return {"ok": true, "error": "", "class_id": class_id, "mission": mission_id, "fields": fields, "extras": extras}


## The fastest speed that still meets the camera's minimum shot interval at this height and front overlap, with a 5 % margin.
static func fp_survey_speed(cam: CameraParams, height_m: float, front_overlap: float, cruise_mps: float) -> float:
	var cap := cam.footprint_m(height_m).y * (1.0 - front_overlap) / cam.min_shot_interval_s
	return snappedf(minf(cruise_mps, 0.95 * cap), 0.05)
