class_name AntennaMount
extends RefCounted
## The antenna mount — a clamp over the two rear standoffs holding a tube the antenna sits in, leaning
## aft. Printed-room slice PR3 (plans/2026-09-14-printed-room-plan.md).
##
## ## The shape
##
## Three closed shells that overlap where they join, which StlWriter allows and every slicer unions:
##
##   - two **standoff rings**, `standoff_spacing_mm` apart, each bored to the standoff plus clearance;
##   - a **bar** between the two ring walls, never reaching either bore;
##   - a **tube**, bored to the antenna's published width plus clearance, leaning aft by
##     `ComponentMesh.WHIP_LEAN_DEGREES` — the angle the antenna is DRAWN at, read from there and never
##     written here, so the mount and the picture cannot come to disagree about it. The tube sits aft
##     of the bar so its bore stays open all the way down, and is lowered until its lowest rim is on
##     the bed.
##
## Printed as it bolts on: Z up, +Y aft, the standoffs along X.
##
## ## What is published and what is guessed
##
##   - **Antenna width: read.** An antenna that does not publish `width_mm` refuses by name. It is the
##     published box's width, which for a whip is the element and for a circular-polarised antenna is
##     the widest part of its cloverleaf — so an RHCP antenna's tube is wide. Honest about the data,
##     not a claim about how every antenna is best held.
##   - **Standoff spacing and diameter: labelled guesses, per drone.** No frame publishes its rear
##     standoffs. They open at 30 mm apart and 5 mm across (an M3 aluminium standoff) and the row says
##     "(guess)" on each until it is set.
##   - **Walls, ring height and tube length:** guesses with no data behind them.
##
## ## Refusal
##
## Between the two ring walls there must be room for the tube and for a bar worth printing. When there
## is not, the part refuses and names the spacing.
##
## ## Mass and drawing
##
## None, and not drawn, for the camera mount's reasons: the antenna's share already holds what it is
## mounted with, and nothing about the drawn whip needs a second object beside it this wave.

const BLOCK := "antenna_mount"
const STANDOFF_SPACING := "standoff_spacing_mm"
const STANDOFF_DIAMETER := "standoff_diameter_mm"
const PART_ID := "antenna_mount"

## Bumped BY HAND whenever `triangles_mm`'s output changes for the same inputs (persistence §7.4).
const GENERATOR_VERSION := 1

const DEFAULT_STANDOFF_SPACING_MM := 30.0
const MIN_STANDOFF_SPACING_MM := 12.0
const MAX_STANDOFF_SPACING_MM := 40.0
const DEFAULT_STANDOFF_DIAMETER_MM := 5.0
const MIN_STANDOFF_DIAMETER_MM := 3.0
const MAX_STANDOFF_DIAMETER_MM := 8.0
const RING_WALL_MM := 1.6
const MIN_RING_HEIGHT_MM := 6.0
const TUBE_WALL_MM := 1.2
const TUBE_LENGTH_MM := 20.0
## The shortest bar between the ring walls worth printing.
const MIN_BAR_MM := 2.0
const SEGMENTS := 24

const STANDOFF_SPACING_HINT := "Centre-to-centre distance between the two rear standoffs the mount clamps. No frame publishes it, so 30 mm is a guess — measure yours."
const STANDOFF_DIAMETER_HINT := "Across the standoff the rings go over. 5 mm is a guess for an M3 aluminium standoff."


static func settings(printing: Dictionary) -> Dictionary:
	var raw: Variant = printing.get(BLOCK, {})
	return raw if raw is Dictionary else {}


static func set_value(printing: Dictionary, key: String, value: Variant) -> void:
	var block := settings(printing).duplicate(true)
	match key:
		STANDOFF_SPACING:
			block[STANDOFF_SPACING] = clampf(float(value), MIN_STANDOFF_SPACING_MM, MAX_STANDOFF_SPACING_MM)
		STANDOFF_DIAMETER:
			block[STANDOFF_DIAMETER] = clampf(float(value), MIN_STANDOFF_DIAMETER_MM, MAX_STANDOFF_DIAMETER_MM)
		_:
			push_warning("antenna_mount has no setting '%s'" % key)
			return
	printing[BLOCK] = block


## Everything the mount is made from, or a refusal.
static func dimensions(antenna: Dictionary, printing: Dictionary) -> Dictionary:
	var block := settings(printing)
	var spacing_raw: Variant = block.get(STANDOFF_SPACING, null)
	var diameter_raw: Variant = block.get(STANDOFF_DIAMETER, null)
	var spacing_guessed := not (spacing_raw is float or spacing_raw is int)
	var diameter_guessed := not (diameter_raw is float or diameter_raw is int)
	var spacing := DEFAULT_STANDOFF_SPACING_MM if spacing_guessed \
		else clampf(float(spacing_raw), MIN_STANDOFF_SPACING_MM, MAX_STANDOFF_SPACING_MM)
	var diameter := DEFAULT_STANDOFF_DIAMETER_MM if diameter_guessed \
		else clampf(float(diameter_raw), MIN_STANDOFF_DIAMETER_MM, MAX_STANDOFF_DIAMETER_MM)
	var clearance := PrintSettings.clearance_mm(printing)
	var out := {"ok": false, "reason": "", "standoff_spacing_mm": spacing, "standoff_spacing_guessed": spacing_guessed,
		"standoff_diameter_mm": diameter, "standoff_diameter_guessed": diameter_guessed,
		"clearance_mm": clearance, "segments": SEGMENTS, "lean_deg": ComponentMesh.WHIP_LEAN_DEGREES}

	if antenna.is_empty():
		out["reason"] = "%s: no antenna is fitted" % PART_ID
		return out
	var antenna_id := String(antenna.get("part_id", "antenna"))
	var specs: Dictionary = antenna.get("specs", {})
	if specs.get("width_mm") == null or float(specs["width_mm"]) <= 0.0:
		out["reason"] = "%s: %s publishes no width_mm, and the tube's bore is not guessed" % [PART_ID, antenna_id]
		return out

	var width := float(specs["width_mm"])
	var phi := deg_to_rad(ComponentMesh.WHIP_LEAN_DEGREES)
	var ri := diameter * 0.5 + clearance
	var ro := ri + RING_WALL_MM
	var rt := width * 0.5 + clearance
	var big_rt := rt + TUBE_WALL_MM
	out.merge({
		"antenna_width_mm": width,
		"standoff_bore_radius_mm": ri,
		"ring_outer_radius_mm": ro,
		# Tall enough that the leaning tube's forward rim still lands inside the bar it joins.
		"ring_height_mm": maxf(MIN_RING_HEIGHT_MM, 2.0 * big_rt * sin(phi) + TUBE_WALL_MM),
		"bar_half_width_mm": ro * 0.5,
		"tube_bore_radius_mm": rt,
		"tube_outer_radius_mm": big_rt,
		"tube_length_mm": TUBE_LENGTH_MM,
	}, true)

	var between := spacing - 2.0 * ro
	var needed := maxf(2.0 * big_rt, MIN_BAR_MM)
	if between < needed:
		out["reason"] = "%s: standoffs %.1f mm apart%s and %.1f mm across leave %.1f mm between the rings, and the %.1f mm tube for %s needs %.1f mm" % [
			PART_ID, spacing, " (guess)" if spacing_guessed else "", diameter, between, 2.0 * big_rt,
			antenna_id, needed]
		return out
	out["ok"] = true
	return out


## The three shells, separately: `{"rings", "bar", "tube"}`, each a triangle list in millimetres.
## Empty lists for a refused `dims`.
static func shells_mm(dims: Dictionary) -> Dictionary:
	var out := {"rings": [], "bar": [], "tube": []}
	if not bool(dims.get("ok", false)):
		return out
	var n := int(dims["segments"])
	var s := float(dims["standoff_spacing_mm"])
	var ri := float(dims["standoff_bore_radius_mm"])
	var ro := float(dims["ring_outer_radius_mm"])
	var h := float(dims["ring_height_mm"])
	var wb := float(dims["bar_half_width_mm"])
	var rt := float(dims["tube_bore_radius_mm"])
	var big_rt := float(dims["tube_outer_radius_mm"])
	var phi := deg_to_rad(float(dims["lean_deg"]))

	var rings: Array = []
	for side in [-1.0, 1.0]:
		rings.append_array(_annulus(Vector3(side * s * 0.5, 0.0, 0.0), Vector3.RIGHT, Vector3(0.0, 1.0, 0.0),
			Vector3(0.0, 0.0, 1.0), ri, ro, h, n))
	out["rings"] = rings

	var reach := (ri + ro) * 0.5
	out["bar"] = _box(Vector3(-s * 0.5 + reach, -wb, 0.0), Vector3(s * 0.5 - reach, wb, h))

	# The tube's axis leans aft (+Y) from +Z. u × v = axis keeps the annulus wound outward.
	var axis := Vector3(0.0, sin(phi), cos(phi))
	var u := Vector3(1.0, 0.0, 0.0)
	var v := axis.cross(u)
	var base := Vector3(0.0, wb + big_rt * cos(phi) - TUBE_WALL_MM * 0.5, big_rt * sin(phi))
	out["tube"] = _annulus(base, u, v, axis, rt, big_rt, float(dims["tube_length_mm"]), n)
	return out


## The whole mount: the three shells in one list, which is what is written and what is hashed.
static func triangles_mm(dims: Dictionary) -> Array:
	var shells := shells_mm(dims)
	var out: Array = []
	out.append_array(shells["rings"])
	out.append_array(shells["bar"])
	out.append_array(shells["tube"])
	return out


## A closed annular prism, N-gon inner and outer, from `base` along `w` for `length`. `u × v` must be
## `w`. Wound exactly as ArmGuard's sleeve is, with a polygon for its rectangle.
static func _annulus(base: Vector3, u: Vector3, v: Vector3, w: Vector3, ri: float, ro: float,
		length: float, n: int) -> Array:
	var out: Array = []
	for k in n:
		var ca := cos(TAU / n * k)
		var sa := sin(TAU / n * k)
		var cb := cos(TAU / n * ((k + 1) % n))
		var sb := sin(TAU / n * ((k + 1) % n))
		var ib_a := base + (u * ca + v * sa) * ri
		var ib_b := base + (u * cb + v * sb) * ri
		var ob_a := base + (u * ca + v * sa) * ro
		var ob_b := base + (u * cb + v * sb) * ro
		var top := w * length
		var it_a := ib_a + top
		var it_b := ib_b + top
		var ot_a := ob_a + top
		var ot_b := ob_b + top
		out.append(PackedVector3Array([ob_a, ob_b, ot_b]))
		out.append(PackedVector3Array([ob_a, ot_b, ot_a]))
		out.append(PackedVector3Array([ib_a, it_b, ib_b]))
		out.append(PackedVector3Array([ib_a, it_a, it_b]))
		out.append(PackedVector3Array([it_a, ot_a, ot_b]))
		out.append(PackedVector3Array([it_a, ot_b, it_b]))
		out.append(PackedVector3Array([ib_a, ob_b, ob_a]))
		out.append(PackedVector3Array([ib_a, ib_b, ob_b]))
	return out


## An axis-aligned closed box, wound outward.
static func _box(lo: Vector3, hi: Vector3) -> Array:
	var p := func(i: int, j: int, k: int) -> Vector3:
		return Vector3(hi.x if i == 1 else lo.x, hi.y if j == 1 else lo.y, hi.z if k == 1 else lo.z)
	var faces := [
		[p.call(1, 0, 0), p.call(1, 1, 0), p.call(1, 1, 1), p.call(1, 0, 1)],
		[p.call(0, 0, 0), p.call(0, 0, 1), p.call(0, 1, 1), p.call(0, 1, 0)],
		[p.call(0, 1, 0), p.call(0, 1, 1), p.call(1, 1, 1), p.call(1, 1, 0)],
		[p.call(0, 0, 0), p.call(1, 0, 0), p.call(1, 0, 1), p.call(0, 0, 1)],
		[p.call(0, 0, 1), p.call(1, 0, 1), p.call(1, 1, 1), p.call(0, 1, 1)],
		[p.call(0, 0, 0), p.call(0, 1, 0), p.call(1, 1, 0), p.call(1, 0, 0)],
	]
	var out: Array = []
	for f in faces:
		out.append(PackedVector3Array([f[0], f[1], f[2]]))
		out.append(PackedVector3Array([f[0], f[2], f[3]]))
	return out
