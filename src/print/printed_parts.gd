class_name PrintedParts
extends RefCounted
## What THIS build can send to a printer — the Printed room's parts list, printed-room slices PR0–PR1.
##
## Generated from the build, never a catalog category. There is no SKU for a TPU mount: it is a
## function of the parts it fits and of the drone's printing decisions (design §3 decision 2), which
## the build carries as `build.printing`.
##
## Each row is `{"id", "label", "note", "exportable", "fittable", "fitted"}`. A row that is listed and
## not exportable says why in `note`, because a greyed button with no reason is the stub again.
## `fittable` rows are the ones whose mass the builder switches on here; the prop guard is not one.
##
## THE PROP GUARD IS LISTED, NEVER PICKED. Propulsion owns it — it is physics-bearing, and a second
## rail choosing the same part is the "two lists that were never the same list" P10f found. So the
## row exists only when the build already fits one, and says where it is chosen.

const PROP_GUARD := "prop_guard"
const ARM_GUARD := ArmGuard.PART_ID


static func for_build(build: Build) -> Array:
	var rows: Array = []
	if build == null:
		return rows
	if not build.frame.is_empty():
		rows.append(_arm_guard_row(build))
	if not build.guard.is_empty():
		rows.append({
			"id": PROP_GUARD,
			"label": "Prop guard — %s" % String(build.guard.get("name", build.guard.get("part_id", ""))),
			"note": "Chosen under Propulsion. One ring, print four.",
			"exportable": true,
			"fittable": false,
			"fitted": true,
		})
	return rows


## The arm guard's row. Its note is where the guesses are said: every number the sleeve is made from
## that the catalog did not publish is named as a guess, beside the button that prints it.
static func _arm_guard_row(build: Build) -> Dictionary:
	var dims := ArmGuard.dimensions(build.frame, build.printing)
	var fitted := ArmGuard.is_fitted(build.printing)
	var note := ""
	if not bool(dims["ok"]):
		note = String(dims["reason"])
	else:
		note = "Arm %.1f mm thick (published), %.1f mm wide%s. Wall %.1f mm, length %.0f mm (guesses). %.2f g each, print four%s." % [
			float(dims["arm_thickness_mm"]), float(dims["tip_width_mm"]),
			" (guess)" if bool(dims["tip_width_guessed"]) else "",
			float(dims["wall_mm"]), float(dims["length_mm"]), ArmGuard.mass_kg(dims) * 1000.0,
			"" if fitted else " — not counted in the weight until fitted"]
	return {
		"id": ARM_GUARD,
		"label": "Arm guards — TPU sleeve",
		"note": note,
		"exportable": bool(dims["ok"]),
		"fittable": bool(dims["ok"]),
		"fitted": fitted and bool(dims["ok"]),
	}
