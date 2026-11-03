class_name MotorPresetFigures
extends RefCounted
## The flight figures of every shelf motor, computed live, for the Motor Designer M3/M4 guard
## (tests/test_motor_presets.gd compares them with tests/fixtures/motor_preset_figures.json, which
## was snapshotted BEFORE the presets gained Rm/Io and before the drone read the new motor model).
##
## Two sets: (1) each of the 16 shelf motors on the reference airframe with its own thrust-test
## prop and a pack of the same cell count as its test voltage; (2) every drone-class seed build.

const FIXTURE := "res://tests/fixtures/motor_preset_figures.json"
const FIELDS := ["auw_g", "thrust_to_weight", "hover_throttle", "flight_time_min", "top_speed_kmh"]


static func _figures(b: Build) -> Dictionary:
	return {
		"auw_g": b.all_up_weight_g(),
		"thrust_to_weight": b.thrust_to_weight(),
		"hover_throttle": b.hover_throttle(),
		"flight_time_min": b.flight_time_min(),
		"top_speed_kmh": b.top_speed_kmh(),
	}


static func snapshot() -> Dictionary:
	var catalog := PartsCatalog.load_default()
	var out := {}
	for raw in JsonStore.read_document("res://data/parts/motors.json").get("parts", []):
		var mid := String(raw["part_id"])
		var m: Dictionary = catalog.get_part(mid)
		var b := Build.from_ids(catalog, ReferenceBuild.FRAME_ID, mid,
			String(m["thrust_test"]["prop_id"]), ReferenceBuild.BATTERY_ID)
		out["motor/" + mid] = _figures(b)
	for cid in DroneClass.ids():
		var p := DroneClass.parts_for(cid)
		if p.is_empty():
			continue
		var b2 := Build.from_ids(catalog, String(p["frame"]), String(p["motor"]),
			String(p["propeller"]), String(p["battery"]), String(p["esc"]), String(p["flight_controller"]))
		out["class/" + cid] = _figures(b2)
	return out
