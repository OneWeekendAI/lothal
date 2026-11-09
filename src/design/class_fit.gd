class_name ClassFit
extends RefCounted
## Which catalog parts are made for a drone class, as the shelf shows them. Pure.
##
## This is a SHELF judgement and never a refusal: a part outside the class is listed under "does not
## fit this drone" with a one-line reason, and a click on it still swaps (PartSwap.judge is the only
## judge of what is physically impossible). What it reads is the class record's own typical figures
## (DroneClass `cells`, `prop_in`) and the catalog part's own numbers:
##
## - battery    series cell count inside the class's range
## - propeller  diameter inside the class's prop range, give or take PROP_SLACK_IN
## - motor      the diameter of the prop the motor's own thrust test was run on (the catalog's
##              sourced `thrust_test.prop_id`) inside the class's prop range, give or take
##              MOTOR_TEST_SLACK_IN. A motor's stator size says less than the prop it was tested on.
##
## The class's own seed part is always inside its class (X-Class flies a 6S pack with the 8-12S range
## stated, because the catalog has no 8S+ pack: the seed's comment in DroneClass says so).

## GUESS, display and ordering only: how far past the class's typical prop sizes a prop may be and
## still read as "made for this class" (a 5" frame takes 4.5" to 5.5"). Never reaches physics.
const PROP_SLACK_IN := 0.5
## GUESS, same use: how far the motor's tested prop may be from the class's prop range.
const MOTOR_TEST_SLACK_IN := 1.0


## {fits: bool, reason: String}. Categories this does not judge (frame, electronics, camera...) fit.
static func verdict(class_id: String, category: String, part_id: String, catalog: PartsCatalog) -> Dictionary:
	var c := DroneClass.by_id(class_id)
	var part := catalog.get_part(part_id)
	if c.is_empty() or part.is_empty() or part_id == String(DroneClass.parts_for(class_id).get(category, "")):
		return {"fits": true, "reason": ""}
	var cells: Vector2i = c.get("cells", Vector2i.ZERO)
	var props: Vector2 = c.get("prop_in", Vector2.ZERO)
	var specs: Dictionary = part.get("specs", {})
	match category:
		"battery":
			var n := int(specs.get("cells", 0))
			if cells != Vector2i.ZERO and n > 0 and (n < cells.x or n > cells.y):
				return {"fits": false, "reason": "A %dS pack; this class flies %s." % [n, cells_text(cells)]}
		"propeller":
			var d := float(specs.get("diameter_inches", 0.0))
			if props != Vector2.ZERO and d > 0.0 and (d < props.x - PROP_SLACK_IN or d > props.y + PROP_SLACK_IN):
				return {"fits": false, "reason": "A %s\" prop; this class flies %s props." % [_trim(d), props_text(props)]}
		"motor":
			var tested := catalog.get_part(String(part.get("thrust_test", {}).get("prop_id", "")))
			var d := float(tested.get("specs", {}).get("diameter_inches", 0.0))
			if props != Vector2.ZERO and d > 0.0 and (d < props.x - MOTOR_TEST_SLACK_IN or d > props.y + MOTOR_TEST_SLACK_IN):
				return {"fits": false, "reason": "Tested on a %s\" prop; this class flies %s props." % [_trim(d), props_text(props)]}
	return {"fits": true, "reason": ""}


static func cells_text(r: Vector2i) -> String:
	return "%dS" % r.x if r.x == r.y else "%d-%dS" % [r.x, r.y]


static func props_text(r: Vector2) -> String:
	return "%s\"" % _trim(r.x) if is_equal_approx(r.x, r.y) else "%s-%s\"" % [_trim(r.x), _trim(r.y)]


static func _trim(v: float) -> String:
	return ("%.2f" % v).rstrip("0").rstrip(".")
