class_name StructureDetails
extends AirframePanel
## The Structure tab — airframe.md §3.2–§3.4. What the frame weighs, where its centre of gravity
## is, and how hard it is to rotate, all integrated over the plates rather than looked up.
##
## ## The row that is allowed to be embarrassing
##
## `Mass from geometry` prints its disagreement with the published figure, always, including when
## that disagreement is −48%. §9a is explicit that the residual is outline topology — this document
## models a centre plate and four arms, and a real Evoque has five plate thicknesses, side plates,
## a camera plate and a stack cage — so the gap is a statement about what is not modelled yet, not
## about a wrong spec. Hiding it would turn a known, diagnosed limitation into a silent one.
##
## ## Why the inertias are here and not on a physics screen
##
## Inertia is the single most consequential thing a frame decides and the least visible. §2 already
## flags `arm_mm` as the sleeper spec because it is SQUARED — a 7" frame has roughly four times the
## roll inertia of a 3" from geometry alone — and until this tab there was nowhere in the app a
## builder could see that happen while flipping between frames. The three figures are quoted about
## the axes the flight model actually integrates (physics.md §1), not about the plate normal, which
## is the transposition trap AirframeProperties' header spends a screen on.

const SPEC_ROWS := [
	{"key": "stock", "label": "Plate · arm stock"},
	{"key": "plates", "label": "Plates modelled"},
	{"key": "computed_mass", "label": "Mass from geometry"},
	{"key": "published_mass", "label": "Published by the vendor"},
	{"key": "mass_gap", "label": "Difference"},
	# ---- WHERE THE MASS IS (§3.3, §3.4) ----
	{"key": "cg", "label": "Centre of gravity"},
	{"key": "roll_inertia", "label": "Roll inertia"},
	{"key": "pitch_inertia", "label": "Pitch inertia"},
	{"key": "yaw_inertia", "label": "Yaw inertia"},
	{"key": "agility", "label": "Roll : pitch"},
	{"key": "heaviest", "label": "Largest contributor"},
]


func _init() -> void:
	super(SPEC_ROWS)


func row_text(key: String) -> String:
	match key:
		"stock":
			# The two thicknesses are shown SEPARATELY and never averaged into one number. A real
			# arm is thicker stock than the centre plates, and collapsing them was exactly the
			# assumption that put the computed resonance a factor of 6.7 off (§9a).
			#
			# Read off the PLATES, not off a catalog spec: an authored frame has no catalog row, and
			# a frame with three different plate thicknesses (which every real one has) can say so.
			if _document == null:
				return "—"
			if _document.plates.is_empty():
				# A moulded frame has no plates by construction (§0), which is a different statement
				# from "nobody has drawn any yet" — and the difference is the one this row exists to
				# make, since every figure below it is an integral over plates.
				return "— (not a plate frame)" if not _document.motors.is_empty() else "—"
			var structural := _thicknesses(false)
			var arms := _thicknesses(true)
			if structural.is_empty() and arms.is_empty():
				return "—"
			if arms.is_empty():
				return "%s plate" % _thickness_list(structural)
			if structural.is_empty():
				return "%s arm" % _thickness_list(arms)
			return "%s plate · %s arm" % [_thickness_list(structural), _thickness_list(arms)]

		"plates":
			if _document == null:
				return "—"
			var roles: Dictionary = {}
			for plate in _document.plates:
				var role := str(plate.get("role", "plate"))
				roles[role] = int(roles.get(role, 0)) + 1
			if roles.is_empty():
				return "—"
			var parts: Array[String] = []
			for role in roles:
				parts.append("%d %s" % [int(roles[role]), role])
			return ", ".join(parts)

		"computed_mass":
			if _props == null or _props.total_mass_g() <= 0.0:
				return "—"
			return "%.0f g" % _props.total_mass_g()

		"published_mass":
			# Absent for a frame somebody drew, and that is not a missing value: a frame you cut
			# yourself has no vendor to disagree with.
			var published := _document.published_mass_g if _document != null else 0.0
			if published <= 0.0:
				return "— (no vendor figure — this frame is yours)"
			return "%.0f g" % published

		"mass_gap":
			var published := _document.published_mass_g if _document != null else 0.0
			if _props == null or _props.total_mass_g() <= 0.0 or published <= 0.0:
				return "—"
			var computed := _props.total_mass_g()
			var delta := (computed - published) / published * 100.0
			# The diagnosis travels with the number. A reader seeing −48% deserves to know it is a
			# topology gap that A7/A8 closes, not a spec somebody typed wrong.
			var note := "outline is incomplete" if delta < -10.0 else (
				"modelled outline is larger than the real one" if delta > 10.0 else "within 10%")
			return "%+.0f%%  (%s)" % [delta, note]

		"cg":
			if _props == null:
				return "—"
			# Reported as an OFFSET from the geometric origin, because zero is the answer a
			# symmetric frame should give and a reader can check that at a glance. A raw coordinate
			# triple would make "is this frame balanced" an arithmetic exercise.
			var cg := _props.cg_m
			var offset := Vector2(cg.x, cg.z).length() * 1000.0
			if offset < 0.5:
				return "centred  (< 0.5 mm off axis)"
			return "%.1f mm off axis  (x %+.1f, aft %+.1f)" % [
				offset, cg.x * 1000.0, cg.z * 1000.0]

		"roll_inertia":
			return _inertia(_props.roll_inertia_kg_m2() if _props != null else 0.0)

		"pitch_inertia":
			return _inertia(_props.pitch_inertia_kg_m2() if _props != null else 0.0)

		"yaw_inertia":
			return _inertia(_props.yaw_inertia_kg_m2() if _props != null else 0.0)

		"agility":
			if _props == null:
				return "—"
			var roll := _props.roll_inertia_kg_m2()
			var pitch := _props.pitch_inertia_kg_m2()
			if roll <= 0.0 or pitch <= 0.0:
				return "—"
			# A symmetric X is 1.00 by construction; a deadcat or a stretched frame is not, and the
			# ratio is the shortest way to say "this one rolls faster than it pitches".
			var ratio := roll / pitch
			var reading := "rolls and pitches alike"
			if ratio < 0.95:
				reading = "rolls faster than it pitches"
			elif ratio > 1.05:
				reading = "pitches faster than it rolls"
			return "%.2f : 1  (%s)" % [ratio, reading]

		"heaviest":
			if _props == null or _props.contributions.is_empty():
				return "—"
			var best: Dictionary = {}
			var best_mass := -1.0
			for item in _props.contributions:
				var mass := float(item.get("mass_kg", 0.0))
				if mass > best_mass:
					best_mass = mass
					best = item
			if best.is_empty() or _props.total_mass_kg <= 0.0:
				return "—"
			return "%s  (%.0f g, %.0f%%)" % [
				str(best.get("label", "?")), best_mass * 1000.0,
				best_mass / _props.total_mass_kg * 100.0]

	return super(key)


## Every distinct plate thickness in the document, arms or not, in ascending order. Distinct rather
## than averaged: a frame is cut from the stock it is cut from, and the mean of 2 mm and 5 mm is a
## thickness nobody sells.
func _thicknesses(arms: bool) -> Array:
	var seen: Array = []
	for plate in _document.plates:
		var is_arm := str(plate.get("role", "")) == AirframeDocument.ROLE_ARM
		if is_arm != arms:
			continue
		var thickness := AirframeDocument.plate_thickness_mm(plate)
		if thickness > 0.0 and not seen.has(thickness):
			seen.append(thickness)
	seen.sort()
	return seen


static func _thickness_list(thicknesses: Array) -> String:
	var parts: Array[String] = []
	for value in thicknesses:
		parts.append("%.1f" % float(value))
	return "%s mm" % " / ".join(parts)


## An inertia in the units a reader can hold. kg·m² is the SI figure and it is four leading zeros
## on every frame in the catalog, so it is quoted in g·m² — same number, readable magnitude — with
## the SI value beside it for anyone checking against the flight model.
static func _inertia(value_kg_m2: float) -> String:
	if value_kg_m2 <= 0.0:
		return "—"
	# Godot's % operator has no %e, and String.num_scientific prints the full double — seventeen
	# digits of "0.00044491802460333633", which is not a number anybody reads. Fixed to six decimals
	# instead: enough to check against the flight model, short enough to sit in a row.
	return "%.2f g·m²  (%s kg·m²)" % [value_kg_m2 * 1000.0, String.num(value_kg_m2, 6)]
