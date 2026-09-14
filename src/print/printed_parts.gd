class_name PrintedParts
extends RefCounted
## What THIS build can send to a printer — the Printed room's parts list, printed-room slice PR0.
##
## Generated from the build, never a catalog category. There is no SKU for a TPU mount: it is a
## function of the parts it fits and of the drone's printing decisions (design §3 decision 2).
##
## Each row is `{"id", "label", "note", "exportable"}`. A row that is listed and not exportable says
## why in `note`, because a greyed button with no reason is the stub again.
##
## THE PROP GUARD IS LISTED, NEVER PICKED. Propulsion owns it — it is physics-bearing, and a second
## rail choosing the same part is the "two lists that were never the same list" P10f found. So the
## row exists only when the build already fits one, and says where it is chosen.

const PROP_GUARD := "prop_guard"


static func for_build(build: Build) -> Array:
	var rows: Array = []
	if build == null:
		return rows
	if not build.guard.is_empty():
		rows.append({
			"id": PROP_GUARD,
			"label": "Prop guard — %s" % String(build.guard.get("name", build.guard.get("part_id", ""))),
			"note": "Chosen under Propulsion. One ring, print four.",
			"exportable": true,
		})
	return rows
