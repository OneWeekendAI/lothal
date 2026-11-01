class_name SwapLook
extends RefCounted
## How a swapped part changes in the 3D view (Section 3). The class model was drawn for its seed
## parts (tools/blender/build_drone.py, every pack and part sized from the catalog); a swap scales
## the drawn part by the ratio of the new catalog dimensions to the drawn one's, about the face it
## sits on, so a bigger pack is bigger by exactly what the catalog says and still sits on its pad.
## Pure: the caller hands in the drawn node transforms and applies what comes back.
##
## Ratios, per node (catalog fields, never a guess):
##   battery   Build.battery_size_of laid flat (as drawn), about the pack's underside
##   motor_*   bell diameter and height (stator x bell ratio), about the arm pad
##   prop_*    diameter across the disc; lifted with the motor's height
##   stack     StackMesh.size_m of the flight controller's pattern, across the plate
##   camera    Build.component_size_of, about the camera's own centre
##   antennas  Build.component_size_of of the antenna, about its root
## A part that is "not fitted" is hidden. Receiver and guard have no drawn node on the 5".

const NODES := ["battery", "camera", "stack", "antennas",
	"motor_FL", "motor_FR", "motor_BL", "motor_BR", "prop_FL", "prop_FR", "prop_BL", "prop_BR"]


## `base`: node name -> {xf: Transform3D (as drawn), pivot: Vector3 (local)}. `drawn` and `now` are
## selections (category -> id). Returns node name -> {xf, visible, scale: Vector3}.
static func transforms(base: Dictionary, drawn: Dictionary, now: Dictionary,
		catalog: PartsCatalog) -> Dictionary:
	var out := {}
	var motor_r := ratio_for("motor", drawn, now, catalog)
	for node_name in base:
		var b: Dictionary = base[node_name]
		var xf: Transform3D = b["xf"]
		var pivot: Vector3 = b.get("pivot", Vector3.ZERO)
		var cat := category_of(String(node_name))
		var shown := String(now.get(cat, "")) != ""
		var r := ratio_for(cat, drawn, now, catalog) if shown else Vector3.ONE
		var local := Transform3D(Basis.from_scale(r), pivot - pivot * r)
		var nxf := xf * local
		if String(node_name).begins_with("prop_"):
			var corner := String(node_name).substr(5)
			var motor_base: Dictionary = base.get("motor_" + corner, {})
			if not motor_base.is_empty():
				var my := (motor_base["xf"] as Transform3D).origin.y
				nxf.origin.y = my + (xf.origin.y - my) * motor_r.y
		out[node_name] = {"xf": nxf, "visible": shown, "scale": r}
	return out


## The catalog category a drawn node stands for.
static func category_of(node_name: String) -> String:
	if node_name.begins_with("motor_"):
		return "motor"
	if node_name.begins_with("prop_"):
		return "propeller"
	match node_name:
		"stack": return "flight_controller"
		"antennas": return "antenna"
	return node_name


## The (x, y, z) scale from the drawn part of `category` to the fitted one. ONE when either is
## missing or undimensioned, so an unknown part is drawn as drawn rather than as a guess.
static func ratio_for(category: String, drawn: Dictionary, now: Dictionary,
		catalog: PartsCatalog) -> Vector3:
	var a := catalog.get_part(String(drawn.get(category, "")))
	var b := catalog.get_part(String(now.get(category, "")))
	if a.is_empty() or b.is_empty():
		return Vector3.ONE
	var sa := size_of(category, a)
	var sb := size_of(category, b)
	if sa.x <= 0.0 or sa.y <= 0.0 or sa.z <= 0.0:
		return Vector3.ONE
	return Vector3(sb.x / sa.x, sb.y / sa.y, sb.z / sa.z)


## The catalog size that sets a category's drawn scale, metres (x across, y up, z along).
static func size_of(category: String, part: Dictionary) -> Vector3:
	var s: Dictionary = part.get("specs", {})
	match category:
		"battery":
			# Drawn FLAT, as build_drone.py lays every pack: the larger section dimension across.
			var v := Build.battery_size_of(part)
			return Vector3(maxf(v.x, v.y), minf(v.x, v.y), v.z)
		"motor":
			var d := float(s.get("stator_diameter_mm", 0.0)) * float(s.get("bell_diameter_ratio", 1.0))
			var h := float(s.get("stator_height_mm", 0.0)) * float(s.get("bell_height_ratio", 1.0))
			return Vector3(d, h, d) / 1000.0
		"propeller":
			var dia := float(s.get("diameter_inches", 0.0)) * 0.0254
			return Vector3(dia, 1.0, dia)
		"flight_controller":
			var sz := StackMesh.size_m(String(part.get("mounting", {}).get("pattern", "")))
			return Vector3(sz.x, 1.0, sz.z)
		"camera", "antenna":
			if not s.has("length_mm"):
				return Vector3.ZERO
			return Build.component_size_of(part)
	return Vector3.ZERO


## The label a swapped pack wears on its top face: "6S 1300 MAH 100C".
static func pack_label(part: Dictionary) -> String:
	var s: Dictionary = part.get("specs", {})
	return "%dS %d MAH %dC" % [int(s.get("cells", 0)), int(s.get("mah", 0)), int(s.get("c_rating", 0))]
