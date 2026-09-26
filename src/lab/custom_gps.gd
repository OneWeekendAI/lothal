class_name CustomGps
extends CustomComponents
## The GPS modules a builder entered themselves (C7). Read CustomComponents for the box-and-mass
## half every one of these shares, and CustomParts for the id space and the document.
##
## ---------------------------------------------------------------------------
## `mast_height_mm` IS REQUIRED, AND ZERO IS AN ANSWER WHERE ABSENT IS NOT
## ---------------------------------------------------------------------------
##
## This is the one refusal the store exists to make, and it is stricter than the catalog reader
## on purpose. `Build.component_rise_m` reads a missing mast as 0 — right for a camera, which never
## has one — so a custom GPS with the field left off would be seated flat on the top plate whether
## or not it stands 70 mm up on a stalk. That is the case gps.json's `_schema` calls "mass in the
## wrong place": the highest mass on the aircraft and the single thing fitted that moves the centre
## of mass vertically more than anything else, silently put back down.
##
## And there is a second, quieter failure behind the first. `Build.rise_m_for` applies the
## builder's typed mast (C6's field) ONLY to a part whose specs DECLARE `mast_height_mm` — so a
## record missing the key would not merely default wrong, it would ignore the mast field beside the
## row as well, and the builder correcting it on screen would see nothing move.
##
## So a flat module says 0 out loud, the way every flat entry in gps.json does, and a record that
## says nothing is refused. A negative mast is refused too: a module does not hang below the plate
## it is fitted on top of. A string "45" is refused rather than coerced, for the reason
## tests/test_control_parts.gd refuses it in the shipped file — a typed field is the check.
##
## NO DEFAULT, NO CARVED SHARE. A GPS is ADDED mass (design §3): it was never in the electronics
## budget, so nothing here touches Build.CARVED_SHARES or Build.DEFAULT_COMPONENT_IDS, and a custom
## GPS that nobody fits costs the reference build nothing at all.
##
## What is browsing metadata — constellations, compass, protocol — goes in `catalog` for the reason
## gps.json gives: there is no navigation in Lothal, and a GPS here is mass, height and a port.

const GPS_KEY := "gps"


func array_key() -> String:
	return GPS_KEY


func category() -> String:
	return "gps"


func noun() -> String:
	return "GPS module"


func gps_modules() -> Array:
	return records()


static func load_from(path: String = SAVE_PATH) -> CustomGps:
	var document := CustomGps.new()
	document.read_from(path)
	return document


## `mast_height_mm` NAN means "not entered", and becomes an ABSENT key rather than a number — which
## is what lets a dialog with an empty mast field reach the refusal below instead of writing a 0 the
## builder never typed. JSON has no NAN, so absent is also the only honest spelling on disk.
static func make_record(name: String, mass_g: float, length_mm: float, width_mm: float,
		height_mm: float, mast_height_mm: float, constellations: String, compass: bool,
		protocol: String, source: String) -> Dictionary:
	var record := component_record(id_for(name), name, "gps", mass_g, length_mm, width_mm,
		height_mm, {"constellations": constellations, "compass": compass, "protocol": protocol},
		source)
	if not is_nan(mast_height_mm):
		(record["specs"] as Dictionary)["mast_height_mm"] = mast_height_mm
	return record


static func id_for(name: String) -> String:
	return CustomParts.id_for_name(name, "gps")


func _category_problems(record: Dictionary, catalog: PartsCatalog) -> Array[String]:
	var problems := super(record, catalog)
	var raw_specs: Variant = record.get("specs", null)
	if not (raw_specs is Dictionary):
		return problems   # the base already said specs is missing; one message, not two
	var specs := raw_specs as Dictionary

	if not specs.has("mast_height_mm"):
		problems.append("specs.mast_height_mm is required — 0 for a flat module, the stalk's height for a masted one. Left out, the module is seated flat on the top plate whatever it really stands on, and the mast field beside it does nothing")
	else:
		var mast: Variant = specs["mast_height_mm"]
		if not (mast is float or mast is int):
			problems.append("specs.mast_height_mm must be a number of millimetres, not %s" % type_string(typeof(mast)))
		elif float(mast) < 0.0:
			problems.append("specs.mast_height_mm cannot be negative — a GPS stands above the plate it is fitted to, never below it")
	return problems
