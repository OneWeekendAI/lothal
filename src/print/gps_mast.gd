class_name GpsMast
extends RefCounted
## The GPS mast — a printed stalk that holds a GPS module above the top plate. Printed-room slice PR10
## (plans/2026-09-14-printed-room-plan.md).
##
## ## The shape
##
## Three closed shells that overlap where they join, which StlWriter allows and every slicer unions:
##
##   - a **flange** at the foot, a square slab that sits on the plate;
##   - a hollow **post** the mast height tall, bored for the GPS lead;
##   - a **pad** on top, the GPS module's published footprint, for the module to be taped or zip-tied to.
##
## Printed as it stands: Z up, the post on the Z axis, the flange at Z = 0.
##
## ## What is published and what is guessed
##
##   - **Mast height: the assembly's**, `Build.rise_m_for(gps)`: the builder's GPS mast tweak when set,
##     otherwise the module's own `mast_height_mm`. Like the camera tilt it is ONE global setting, so the
##     export records it as an input (PR5 names it from/to).
##   - **Footprint: read.** The pad is the module's `length_mm` × `width_mm`. A GPS that does not publish
##     them refuses by name.
##   - **Lead bore, post wall, pad and flange: guesses**, per drone in `Project.printing.gps_mast`, each
##     labelled "(guess)" on the row.
##   - **Clearance does not apply.** Nothing on this part slides over a bought part: the lead threads a
##     bore far wider than it, the module is taped to a pad, and the flange sits on a plate.
##
## ## Refusal
##
## A GPS with no mast (height 0) has nothing to print, and refuses naming the module. A post whose bore
## leaves no wall refuses too.
##
## ## Mass: opt-in, on the mast
##
## MountLayout says the stalk's own mass is not modelled (its `seated_centre_m` header), so nothing counts
## it twice. When Fitted, the mast is ONE point mass over the GPS bay at half the mast height, the
## middle of the post that is most of its mass. Nothing is added unless the builder ticks Fitted, and the
## reference build fits no GPS at all, so it stays at 507.48 g.

const BLOCK := "gps_mast"
const FITTED := "fitted"
const BORE := "lead_bore_mm"
const WALL := "post_wall_mm"
const PAD := "pad_thickness_mm"
const FLANGE := "flange_mm"
const PART_ID := "gps_mast"

## Bumped BY HAND whenever `triangles_mm`'s output changes for the same inputs (persistence §7.4).
const GENERATOR_VERSION := 1

const DEFAULT_BORE_MM := 3.0
const DEFAULT_WALL_MM := 1.6
const DEFAULT_PAD_MM := 2.0
const DEFAULT_FLANGE_MM := 14.0
const FLANGE_THICKNESS_MM := 2.0
const MIN_WALL_MM := 0.8
const SEGMENTS := 24

const RANGES := {
	BORE: [1.5, 8.0],
	WALL: [0.8, 4.0],
	PAD: [1.0, 5.0],
	FLANGE: [8.0, 30.0],
}


static func settings(printing: Dictionary) -> Dictionary:
	var raw: Variant = printing.get(BLOCK, {})
	return raw if raw is Dictionary else {}


static func is_fitted(printing: Dictionary) -> bool:
	return bool(settings(printing).get(FITTED, false))


static func set_value(printing: Dictionary, key: String, value: Variant) -> void:
	var block := settings(printing).duplicate(true)
	if key == FITTED:
		block[FITTED] = bool(value)
	elif RANGES.has(key):
		block[key] = clampf(float(value), float(RANGES[key][0]), float(RANGES[key][1]))
	else:
		push_warning("gps_mast has no setting '%s'" % key)
		return
	printing[BLOCK] = block


static func _value(block: Dictionary, key: String, default_mm: float) -> Array:
	var raw: Variant = block.get(key, null)
	if raw is float or raw is int:
		return [clampf(float(raw), float(RANGES[key][0]), float(RANGES[key][1])), false]
	return [default_mm, true]


## Everything the mast is made from, or a refusal. Reads the build for the GPS and its mast height.
static func dimensions(build: Build, printing: Dictionary) -> Dictionary:
	var block := settings(printing)
	var bore := _value(block, BORE, DEFAULT_BORE_MM)
	var wall := _value(block, WALL, DEFAULT_WALL_MM)
	var pad := _value(block, PAD, DEFAULT_PAD_MM)
	var flange := _value(block, FLANGE, DEFAULT_FLANGE_MM)
	var out := {"ok": false, "reason": "", "segments": SEGMENTS,
		"bore_mm": bore[0], "bore_guessed": bore[1], "post_wall_mm": wall[0], "wall_guessed": wall[1],
		"pad_thickness_mm": pad[0], "pad_guessed": pad[1], "flange_mm": flange[0], "flange_guessed": flange[1],
		"flange_thickness_mm": FLANGE_THICKNESS_MM}

	var gps: Dictionary = build.components.get("gps", {}) if build != null else {}
	if gps.is_empty():
		out["reason"] = "%s: no GPS is fitted" % PART_ID
		return out
	var gps_id := String(gps.get("part_id", "gps"))
	var specs: Dictionary = gps.get("specs", {})
	for field in ["length_mm", "width_mm"]:
		if specs.get(field) == null or float(specs[field]) <= 0.0:
			out["reason"] = "%s: %s publishes no %s, and the pad is not guessed" % [PART_ID, gps_id, field]
			return out
	var mast_mm := build.rise_m_for(gps) * StlWriter.MM_PER_M
	var ri := float(bore[0]) * 0.5
	var ro := ri + float(wall[0])
	out.merge({"gps_length_mm": float(specs["length_mm"]), "gps_width_mm": float(specs["width_mm"]),
		"mast_height_mm": mast_mm, "bore_radius_mm": ri, "post_outer_radius_mm": ro}, true)

	if mast_mm <= 0.0:
		out["reason"] = "%s: %s sits on the plate with no mast, so there is nothing to print" % [PART_ID, gps_id]
		return out
	if float(flange[0]) < 2.0 * ro:
		out["reason"] = "%s: a %.1f mm flange is narrower than the %.1f mm post" % [PART_ID, float(flange[0]), 2.0 * ro]
		return out
	out["ok"] = true
	return out


## The three shells, separately: `{"flange", "post", "pad"}`, millimetres. Empty for a refusal.
static func shells_mm(dims: Dictionary) -> Dictionary:
	var out := {"flange": [], "post": [], "pad": []}
	if not bool(dims.get("ok", false)):
		return out
	var f := float(dims["flange_mm"]) * 0.5
	var h := float(dims["mast_height_mm"])
	var l := float(dims["gps_length_mm"]) * 0.5
	var w := float(dims["gps_width_mm"]) * 0.5
	out["flange"] = AntennaMount._box(Vector3(-f, -f, 0.0), Vector3(f, f, float(dims["flange_thickness_mm"])))
	out["post"] = AntennaMount._annulus(Vector3.ZERO, Vector3(1.0, 0.0, 0.0), Vector3(0.0, 1.0, 0.0),
		Vector3(0.0, 0.0, 1.0), float(dims["bore_radius_mm"]), float(dims["post_outer_radius_mm"]), h,
		int(dims["segments"]))
	out["pad"] = AntennaMount._box(Vector3(-w, -l, h), Vector3(w, l, h + float(dims["pad_thickness_mm"])))
	return out


static func triangles_mm(dims: Dictionary) -> Array:
	var shells := shells_mm(dims)
	var out: Array = []
	out.append_array(shells["flange"])
	out.append_array(shells["post"])
	out.append_array(shells["pad"])
	return out


## The three closed forms, mm³ — post annulus, flange slab and pad slab, summed as the shells overlap.
static func volume_mm3(dims: Dictionary) -> float:
	if not bool(dims.get("ok", false)):
		return 0.0
	var n := int(dims["segments"])
	var gon := n * 0.5 * sin(TAU / n)
	var ri := float(dims["bore_radius_mm"])
	var ro := float(dims["post_outer_radius_mm"])
	return gon * (ro * ro - ri * ri) * float(dims["mast_height_mm"]) \
		+ pow(float(dims["flange_mm"]), 2.0) * float(dims["flange_thickness_mm"]) \
		+ float(dims["gps_length_mm"]) * float(dims["gps_width_mm"]) * float(dims["pad_thickness_mm"])


static func mass_kg(dims: Dictionary) -> float:
	return PrintSettings.printed_mass_kg(volume_mm3(dims))


## One point mass over the GPS bay at half the mast, when fitted and readable; nothing otherwise.
static func part_masses(build: Build, printing: Dictionary) -> Array:
	var out: Array = []
	if not is_fitted(printing):
		return out
	var dims := dimensions(build, printing)
	if not bool(dims["ok"]):
		return out
	var bay := MountLayout.by_id(build.mount_points(), String(Build.COMPONENT_MOUNTS["gps"]))
	if bay == null:
		return out
	var seat := bay.position + Vector3(0.0, bay.normal * float(dims["mast_height_mm"]) * 0.0005, 0.0)
	out.append(PartMass.new(mass_kg(dims), seat, Vector3.ZERO, "GPS mast"))
	return out
