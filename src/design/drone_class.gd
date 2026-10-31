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
## `seed` is {project category: catalog id}.
const CLASSES: Array[Dictionary] = [
	{
		"id": "tiny_whoop", "name": "Tiny Whoop", "use": "Indoor",
		"props": "31–40 mm", "wheelbase": "65–75 mm", "battery": "1S", "auw": "20–35 g",
		"wheelbase_mm": 65.0,
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
		# New class-typical 8" cinelifter frame (sourced from the 7" one). The 2808 1300KV is the
		# catalog's cinelifter motor, thrust-tested by its table on exactly this 8x4.5x3 on 6S; the
		# 6S 4000 Li-ion is the catalog's long-endurance pack.
		"seed": {
			"frame": "frame_8in_cinelifter", "motor": "motor_2808_1300kv",
			"propeller": "prop_8x45x3", "battery": "battery_6s_4000_liion",
			"esc": "esc_4in1_60a_30x30", "flight_controller": "fc_f405_30x30",
			"camera": "cam_digital_hd", "vtx": "vtx_digital_hd",
		},
	},
	{
		"id": "x_class", "name": "X-Class", "use": "Giant racing",
		"props": "10–13\"", "wheelbase": "600–800 mm", "battery": "8–12S", "auw": "3–6 kg",
		"wheelbase_mm": 700.0,
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
