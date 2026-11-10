class_name DroneClass
extends RefCounted
## The drone classes a new project can start from, and the catalog parts each one seeds.
##
## Two kinds of number live here and they must never be confused:
##
## - **Typical figures** (prop size, wheelbase, battery, all-up weight, use) are what a class
##   usually looks like in the hobby. They are DISPLAY TEXT ONLY, always labelled "typical", and
##   nothing reads them as physics. The aircraft the builder gets is weighed by `Build`, and may
##   sit outside its class's typical range. The gap is shown, not hidden.
## - **Seed parts** are catalog ids, the closest sourced preset to each class. Every class has
##   one. Where the catalog had no honest part, a class-typical one was added to data/parts with
##   its own "source" (X-Class is the least sourced); the rationale is in the comment on each seed.
##
## The order of `CLASSES` is the DRAWN size order the picker shows (the ducted 3" cinewhoop, at 160 mm
## wheelbase with its ducts, is physically bigger than a bare Sub-250, so it follows it), and the order the "relative model
## sizes are monotonic" check walks.

const DEFAULT_ID := "five_inch"

## Each entry: id, name, use, and the typical figures as display strings. `wheelbase_mm` is the
## wheelbase of the class's Blender model (tools/blender/build_drone.py CFGS), shown as the size cue.
## `cells` (series count) and `prop_in` (inches) are the same typical line as numbers, read ONLY to
## decide which catalog parts the shelf offers first (ClassFit); they are never physics. `seed` is
## {project category: catalog id}.
const CLASSES: Array[Dictionary] = [
	{
		"id": "tiny_whoop", "name": "Tiny Whoop", "use": "Indoor",
		"props": "31–40 mm", "wheelbase": "65–75 mm", "battery": "1S", "auw": "20–35 g",
		"wheelbase_mm": 65.0,
		"cells": Vector2i(1,1), "prop_in": Vector2(1.22,1.57),
		"seed": {
			"frame": "frame_65mm_whoop_lite", "motor": "motor_0802_19000kv",
			"propeller": "prop_16x12x4", "battery": "battery_1s_300",
			"esc": "esc_aio_5a_whoop", "flight_controller": "fc_f411_25x25_whoop",
			"camera": "cam_nano_analog", "vtx": "vtx_analog_25mw_whoop",
			"antenna": "antenna_dipole_ufl_nano", "receiver": "rx_elrs_2400_nano",
		},
	},
	{
		"id": "toothpick", "name": "Toothpick", "use": "Light outdoor",
		"props": "2–2.5\"", "wheelbase": "90–120 mm", "battery": "1–2S", "auw": "40–80 g",
		"wheelbase_mm": 110.0,
		"cells": Vector2i(1,2), "prop_in": Vector2(2.0,2.5),
		"seed": {
			"frame": "frame_25in_whoop", "motor": "motor_1103_8000kv",
			"propeller": "prop_25x25x4", "battery": "battery_2s_450",
			"esc": "esc_aio_5a_whoop", "flight_controller": "fc_f411_25x25_whoop",
			"camera": "cam_nano_analog", "vtx": "vtx_analog_25mw_whoop",
			"antenna": "antenna_dipole_ufl_nano", "receiver": "rx_elrs_2400_nano",
		},
	},
	{
		"id": "sub250_35", "name": "Sub-250", "use": "Under 250 g",
		"props": "3.5\"", "wheelbase": "150–160 mm", "battery": "4S", "auw": "≤ 249 g",
		"wheelbase_mm": 155.0,
		"cells": Vector2i(4,4), "prop_in": Vector2(3.5,3.5),
		"seed": {
			"frame": "frame_35in_freestyle", "motor": "motor_1404_4600kv",
			"propeller": "prop_35x28x3", "battery": "battery_4s_650",
			"esc": "esc_4in1_20a_20x20", "flight_controller": "fc_f405_20x20",
			"camera": "cam_nano_analog", "vtx": "vtx_analog_400mw",
			"antenna": "antenna_dipole_ufl_nano", "receiver": "rx_elrs_2400_nano",
		},
	},
	{
		"id": "cinewhoop_3", "name": "3\" Cinewhoop", "use": "Smooth video",
		"props": "3\"", "wheelbase": "130–160 mm", "battery": "4S", "auw": "150–250 g",
		"wheelbase_mm": 160.0,
		"cells": Vector2i(4,4), "prop_in": Vector2(3.0,3.0),
		# Sources are on each catalog part (data/parts/*.json "source"). The frame is the new
		# class-typical 3" cinewhoop (70 mm arm, 20x20 stack for the 4S 4-in-1); the 1404 3800KV
		# and 3x3x3 are the catalog's own 3" pair; 4S 650 is the pack the catalog sources to a 3"
		# build (Tattu R-Line 4S 650 mAh, 61 x 31 x 25 mm); the duct is the catalog's 3" TPU shroud.
		"seed": {
			"frame": "frame_3in_cinewhoop", "motor": "motor_1404_3800kv",
			"propeller": "prop_3x3x3", "battery": "battery_4s_650",
			"esc": "esc_4in1_20a_20x20", "flight_controller": "fc_f405_20x20",
			"camera": "cam_nano_analog", "vtx": "vtx_analog_400mw",
			"antenna": "antenna_dipole_ufl_nano", "receiver": "rx_elrs_2400_nano",
			"guard": "guard_duct_3in_tpu",
		},
	},
	{
		"id": "four_inch", "name": "4\"", "use": "Light freestyle",
		"props": "4\"", "wheelbase": "170–180 mm", "battery": "4–6S", "auw": "300–450 g",
		"wheelbase_mm": 175.0,
		"cells": Vector2i(4,6), "prop_in": Vector2(4.0,4.0),
		# New class-typical 4" frame and 4x2.5x3 prop (sources on the parts). 1507 3600KV is the
		# catalog's 4S freestyle motor; 4S 1300 is its 4S pack (155 g); 20 A 4-in-1 and F405 20x20
		# match the frame's 20x20 stack.
		"seed": {
			"frame": "frame_4in_freestyle", "motor": "motor_1507_3600kv",
			"propeller": "prop_4x25x3", "battery": "battery_4s_1300",
			"esc": "esc_4in1_20a_20x20", "flight_controller": "fc_f405_20x20",
			"camera": "cam_nano_analog", "vtx": "vtx_analog_400mw",
			"antenna": "antenna_dipole_ufl_nano", "receiver": "rx_elrs_2400_nano",
		},
	},
	{
		"id": "five_inch", "name": "5\"", "use": "Freestyle and racing",
		"props": "5\"", "wheelbase": "210–230 mm", "battery": "4–6S", "auw": "550–750 g",
		"wheelbase_mm": 220.0,
		"cells": Vector2i(4,6), "prop_in": Vector2(5.0,5.0),
		# The reference build. Read from ReferenceBuild rather than copied, so the default class
		# can never drift from the oracle every other suite pins.
		"seed": {
			"frame": ReferenceBuild.FRAME_ID, "motor": ReferenceBuild.MOTOR_ID,
			"propeller": ReferenceBuild.PROPELLER_ID, "battery": ReferenceBuild.BATTERY_ID,
			"esc": ReferenceBuild.ESC_ID, "flight_controller": ReferenceBuild.FC_ID,
		},
	},
	{
		"id": "six_inch", "name": "6\"", "use": "Longer flights",
		"props": "6\"", "wheelbase": "250 mm", "battery": "6S", "auw": "700–900 g",
		"wheelbase_mm": 250.0,
		"cells": Vector2i(6,6), "prop_in": Vector2(6.0,6.0),
		"seed": {
			"frame": "frame_6in_long_range", "motor": "motor_2506_1500kv",
			"propeller": "prop_6x45x3", "battery": "battery_6s_1300",
			"esc": "esc_4in1_45a_30x30", "flight_controller": "fc_f405_30x30",
		},
	},
	{
		"id": "seven_lr", "name": "7\" Long Range", "use": "Long range",
		"props": "7\"", "wheelbase": "280–300 mm", "battery": "6S", "auw": "0.8–1.2 kg",
		"wheelbase_mm": 290.0,
		"cells": Vector2i(6,6), "prop_in": Vector2(7.0,7.0),
		"seed": {
			"frame": "frame_7in_long_range", "motor": "motor_2807_1300kv",
			"propeller": "prop_7x35x2", "battery": "battery_6s_1300",
			"esc": "esc_4in1_45a_30x30", "flight_controller": "fc_f405_30x30",
			"antenna": "antenna_rhcp_sma_long_range", "receiver": "rx_elrs_900",
		},
	},
	{
		"id": "cinelifter", "name": "Cinelifter", "use": "Cinema cameras",
		"props": "8–10\"", "wheelbase": "350–450 mm", "battery": "6–8S", "auw": "2–4 kg",
		"wheelbase_mm": 400.0,
		"cells": Vector2i(6,8), "prop_in": Vector2(8.0,10.0),
		# SOURCED to one real aircraft: the iFlight Taurus X8 V3 (O4, 6S), a COAXIAL X8 like the
		# Blender model — 400 mm wheelbase, eight XING2 3110 1250KV on HQ 8043 (8x4.3x3) props, a
		# BLITZ E80 80 A stack, DJI O4 Pro, the iFlight Fullsend 6S 5600mAh 95C pack, takeoff weight
		# ~2492 g with that pack and no cinema camera (iflight-rc.eu/en/products/
		# taurus-x8-v3-o4-6s-hd-cinelifter; rcdrone.top lists the same figures). Catalog stand-ins
		# where the exact part is not stocked: the 2808 1300KV (thrust-tested on exactly this 8x4.5x3
		# on 6S) for the 3110 1250KV, the 8x4.5x3 for the HQ 8043, and two 80 A 4-in-1 boards
		# (esc_x8_2x80a, 8 channels) for the E80 stack. The pack IS the Fullsend (battery_6s_5600).
		# The frame says motors_per_arm 2, so Build weighs and drives eight motors.
		"seed": {
			"frame": "frame_8in_cinelifter", "motor": "motor_2808_1300kv",
			"propeller": "prop_8x45x3", "battery": "battery_6s_5600",
			"esc": "esc_x8_2x80a", "flight_controller": "fc_f405_30x30",
			"camera": "cam_dji_o4_pro", "vtx": "vtx_dji_o4_pro",
		},
	},
	{
		"id": "mapper", "name": "Mapper", "use": "Multispectral survey",
		"props": "9.4\"", "wheelbase": "380–400 mm", "battery": "4S", "auw": "1.0–1.5 kg",
		"wheelbase_mm": 400.0,
		"cells": Vector2i(4,4), "prop_in": Vector2(9.4,9.4),
		# MODEL: a labelled STAND-IN. mapper.glb is a byte copy of cinelifter.glb (a 400 mm coaxial-X8 body); a
		# survey quad has no model of its own yet. The size cue (400 mm) matches that model, so it ties the
		# Cinelifter and is placed right after it. SEED: the mapper_* catalog parts (SR9 L4.1, Mavic 3M-like
		# survey airframe, ESTIMATED), the 10 Ah (144 Wh) Li-ion survey pack (4S; the id still says 6S), the 45 A 4-in-1 and F405 30x30 stack (the frame is drilled 30.5x30.5; the 20x20 boards are refused),
		# the RedEdge-class multispectral camera and the RTK GPS. PAYLOAD: 20 W ESTIMATED (sunlight sensor +
		# RTK, over the camera and GPS already in the parts list) and 40 g for the sunlight sensor.
		"seed": {
			"frame": "mapper_frame_380", "motor": "mapper_motor_2008", "propeller": "mapper_prop_94x53",
			"battery": "mapper_battery_4s_10000_liion", "esc": "esc_4in1_45a_30x30", "flight_controller": "fc_f405_30x30",
			"camera": "mapper_cam_multispectral_rededge", "gps": "mapper_gps_rtk",
		},
		"payload": {"w": 20.0, "mass_g": 40.0, "note": "ESTIMATED: sunlight sensor + RTK link; 40 g is the sunlight sensor"},
	},
	{
		"id": "x_class", "name": "X-Class", "use": "Giant racing",
		"props": "10–13\"", "wheelbase": "600–800 mm", "battery": "8–12S", "auw": "3–6 kg",
		"wheelbase_mm": 700.0,
		"cells": Vector2i(8,12), "prop_in": Vector2(10.0,13.0),
		# No new parts: the catalog has no 8S+ pack and no 13" prop that its BEMT solver converges on
		# (a trial 13x4.4x2 diverged in four suites). The closest existing preset is the 10" long-range
		# frame (the top of the class's 10-13" props) on the 10x5x2 bi-blade, the 2808 1300KV and the
		# 6S 4000 Li-ion pack. It is an X-Class by prop size only; the class screen's typical line
		# says what the real class is, and Build weighs this aircraft.
		"seed": {
			"frame": "frame_10in_long_range", "motor": "motor_2808_1300kv",
			"propeller": "prop_10x5x2", "battery": "battery_6s_4000_liion",
			"esc": "esc_4in1_80a_30x30", "flight_controller": "fc_f405_30x30",
			"camera": "cam_digital_hd", "vtx": "vtx_digital_hd",
		},
	},
]


## Default payload of a class (L4.3): {"w", "mass_g", "tag", "note"}. Zero for every class without a `payload` key
## on its CLASSES entry. ESTIMATED always: no catalog part carries a payload figure.
static func payload_for(id: String) -> Dictionary:
	return payload_from_entry(by_id(id))


static func payload_from_entry(entry: Dictionary) -> Dictionary:
	var src: Dictionary = entry.get("payload", {})
	return {"w": float(src.get("w", 0.0)), "mass_g": float(src.get("mass_g", 0.0)), "tag": "estimated", "note": String(src.get("note", ""))}


static func ids() -> Array[String]:
	var out: Array[String] = []
	for entry in CLASSES:
		out.append(String(entry["id"]))
	return out


## The class record, or {} for an unknown id.
static func by_id(id: String) -> Dictionary:
	for entry in CLASSES:
		if String(entry["id"]) == id:
			return entry
	return {}


## Path of the class's Blender model.
static func model_path(id: String) -> String:
	return "res://assets/models/classes/%s.glb" % id


static func is_available(id: String) -> bool:
	return not (by_id(id).get("seed", {}) as Dictionary).is_empty()


## The one line under a class: its typical figures, labelled as typical.
static func typical_line(id: String) -> String:
	var c := by_id(id)
	if c.is_empty():
		return ""
	return "Typical: %s props · %s wheelbase · %s · %s · %s" % [
		c["props"], c["wheelbase"], c["battery"], c["auw"], String(c["use"]).to_lower()]


## Every project category this class decides, resolved: the seed's ids, the carved payload
## defaults where the seed names none, and "" (not fitted) for every other optional category.
## Empty for an unknown class.
static func parts_for(id: String) -> Dictionary:
	var seeded: Dictionary = by_id(id).get("seed", {})
	if seeded.is_empty():
		return {}
	var out: Dictionary = {}
	for category in ProjectSchema.all_categories():
		out[category] = ""
	for category in Build.carved_components():
		out[category] = String(Build.DEFAULT_COMPONENT_IDS[category])
	for category in seeded:
		out[category] = String(seeded[category])
	return out


## Writes the class and its seed parts into `project`. Returns false (and changes nothing) for an
## unknown class.
##
## Only the parts and the class change. The project's name, id, history and every other decision
## block stay; a class picked on a project that had a drawn frame drops the drawing, because a
## drawing belongs to the frame it was drawn on.
static func apply_to(project: Project, id: String) -> bool:
	var parts := parts_for(id)
	if parts.is_empty():
		return false
	if String(project.parts.get("frame", "")) != String(parts["frame"]):
		project.airframe = {}
	for category in parts:
		project.parts[category] = parts[category]
	project.drone_class = id
	return true


## A new project of this class. Named like every other new drone.
static func starting_project(id: String, p_name: String = "") -> Project:
	var project := ProjectLibrary.starting_project(p_name)
	apply_to(project, id)
	return project
