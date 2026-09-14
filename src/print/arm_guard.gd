class_name ArmGuard
extends RefCounted
## The arm guard — a TPU sleeve over each arm tip, inboard of the motor, that takes the crash the
## carbon and the motor leads would otherwise take. Printed-room slice PR1
## (plans/2026-09-14-printed-room-plan.md).
##
## ## What is published and what is guessed
##
## The bore has to fit the arm, so it needs the arm's cross-section at the tip. The catalog publishes
## `arm_thickness_mm` on 11 of 15 frames and `arm_width_mm` — at the ROOT, not the tip — on one. So:
##
##   - **Thickness is read, never guessed.** A frame that does not publish it REFUSES the part, by name.
##     Guessing a second dimension of the one interface that decides fit would make the part a guess
##     twice over, and a TPU sleeve that does not go on the arm is not a part.
##   - **Tip width is a labelled guess.** It opens at the frame's published root width where there is
##     one (a taper only makes the tip narrower, so the sleeve is loose rather than tight), and at
##     10 mm otherwise. `tip_width_guessed` says which, and the panel prints it.
##   - **Wall and length are guesses** with no data behind them at all: 1.6 mm (four perimeters at a
##     0.4 mm nozzle) and 18 mm.
##   - **Clearance is PrintSettings'**, added on every side of the bore.
##
## ## One triangle list
##
## `triangles_mm` is the ONE definition of the solid. `ArmGuardMesh` draws it and the export writes
## it — GuardMesh's rule, for the same reason: the screen draws with culling off, so a sleeve wound
## inside out looks identical there and prints with its outside missing.
##
## ## Mass: opt-in, on top
##
## Nothing is fitted until the builder says so (`fitted`), so the reference build weighs 496.0 g
## with this file present. When fitted, four sleeves are ADDED to the aircraft rather than carved out
## of any budget: no budget ever held them (plan, "Standing decisions"). Each is a point mass at the
## seat `seat_position_m` names — the same function the drawing reads, so the sleeve that is weighed
## is the sleeve that is drawn. Its own tensor is left at zero: at 110 mm out, a 1 g sleeve's
## parallel-axis term is some 400× its local one.

const BLOCK := "arm_guard"
const FITTED := "fitted"
const TIP_WIDTH := "tip_width_mm"
const WALL := "wall_mm"
const LENGTH := "length_mm"

const FALLBACK_TIP_WIDTH_MM := 10.0
const DEFAULT_WALL_MM := 1.6
const DEFAULT_LENGTH_MM := 18.0
const MIN_WALL_MM := 0.8
const MAX_WALL_MM := 4.0
const MIN_LENGTH_MM := 6.0
const MAX_LENGTH_MM := 40.0
const MIN_TIP_WIDTH_MM := 4.0
const MAX_TIP_WIDTH_MM := 30.0

## TPU 95A, 1.22 g/cm³ — the class-typical datasheet figure (Ultimaker and Polymaker TPU 95A sheets
## both sit at 1.20–1.23). A material's density, not this part's, and not re-sourced per brand.
const TPU_DENSITY_KG_M3 := 1220.0
## Fraction of the solid actually filled. A GUESS: a 1.6 mm wall is all perimeters at any slicer's
## defaults, so it prints solid; an 18 mm sleeve with a thicker wall would not.
const INFILL_FRACTION := 1.0

const PART_ID := "arm_guard"
## Bumped BY HAND whenever `triangles_mm`'s output changes for the same inputs (persistence §7.4).
const GENERATOR_VERSION := 1


## This drone's arm-guard block, or an empty one. Read-only: the caller owns `printing`.
static func settings(printing: Dictionary) -> Dictionary:
	var raw: Variant = printing.get(BLOCK, {})
	return raw if raw is Dictionary else {}


static func is_fitted(printing: Dictionary) -> bool:
	return bool(settings(printing).get(FITTED, false))


## Writes one arm-guard value into `printing`, clamped where it is a length.
static func set_value(printing: Dictionary, key: String, value: Variant) -> void:
	var block := settings(printing).duplicate(true)
	match key:
		FITTED:
			block[FITTED] = bool(value)
		TIP_WIDTH:
			block[TIP_WIDTH] = clampf(float(value), MIN_TIP_WIDTH_MM, MAX_TIP_WIDTH_MM)
		WALL:
			block[WALL] = clampf(float(value), MIN_WALL_MM, MAX_WALL_MM)
		LENGTH:
			block[LENGTH] = clampf(float(value), MIN_LENGTH_MM, MAX_LENGTH_MM)
		_:
			push_warning("arm_guard has no setting '%s'" % key)
			return
	printing[BLOCK] = block


## Everything the solid is made from, or a refusal. Returns
## `{"ok", "reason", "arm_thickness_mm", "tip_width_mm", "tip_width_guessed", "wall_mm", "length_mm",
##   "clearance_mm", "bore_width_mm", "bore_height_mm"}`.
static func dimensions(frame: Dictionary, printing: Dictionary) -> Dictionary:
	var specs: Dictionary = frame.get("specs", {})
	var frame_id := String(frame.get("part_id", "frame"))
	var thickness := float(specs.get("arm_thickness_mm", 0.0)) if specs.get("arm_thickness_mm") != null else 0.0
	if thickness <= 0.0:
		return {"ok": false,
			"reason": "%s: %s publishes no arm_thickness_mm, and the bore cannot be guessed twice" % [
				PART_ID, frame_id]}

	var block := settings(printing)
	var guessed := not block.has(TIP_WIDTH)
	var tip_width := FALLBACK_TIP_WIDTH_MM
	if not guessed:
		tip_width = float(block[TIP_WIDTH])
	elif specs.get("arm_width_mm") != null and float(specs["arm_width_mm"]) > 0.0:
		tip_width = float(specs["arm_width_mm"])
	var wall := float(block.get(WALL, DEFAULT_WALL_MM))
	var length := float(block.get(LENGTH, DEFAULT_LENGTH_MM))
	var clearance := PrintSettings.clearance_mm(printing)

	return {
		"ok": true,
		"reason": "",
		"arm_thickness_mm": thickness,
		"tip_width_mm": tip_width,
		"tip_width_guessed": guessed,
		"wall_mm": wall,
		"length_mm": length,
		"clearance_mm": clearance,
		"bore_width_mm": tip_width + 2.0 * clearance,
		"bore_height_mm": thickness + 2.0 * clearance,
	}


## The sleeve as printable triangles: millimetres, lying flat for printing — its bore along X, width
## across Y, height up Z — wound OUTWARD, centred on the origin. Empty for a refused `dims`.
##
## Built exactly as GuardMesh builds its annulus, with a rectangle for the circle: inner and outer
## corners walked counter-clockwise in the (Y, Z) plane and swept along X. The corners are written in
## ring order (first two coordinates the loop, third the axis) and permuted into place at the end; a
## cyclic permutation is a proper rotation, so the winding the ring's recipe gets right survives it.
static func triangles_mm(dims: Dictionary) -> Array:
	var out: Array = []
	if not bool(dims.get("ok", false)):
		return out
	var a := float(dims["bore_width_mm"]) * 0.5
	var b := float(dims["bore_height_mm"]) * 0.5
	var wall := float(dims["wall_mm"])
	var outer_a := a + wall
	var outer_b := b + wall
	var half_l := float(dims["length_mm"]) * 0.5
	if a <= 0.0 or b <= 0.0 or wall <= 0.0 or half_l <= 0.0:
		return out

	var inner := [Vector2(a, -b), Vector2(a, b), Vector2(-a, b), Vector2(-a, -b)]
	var outer := [Vector2(outer_a, -outer_b), Vector2(outer_a, outer_b),
		Vector2(-outer_a, outer_b), Vector2(-outer_a, -outer_b)]

	for i in 4:
		var j := (i + 1) % 4
		var ib_a := _place(inner[i], -half_l)
		var it_a := _place(inner[i], half_l)
		var ot_a := _place(outer[i], half_l)
		var ob_a := _place(outer[i], -half_l)
		var ib_b := _place(inner[j], -half_l)
		var it_b := _place(inner[j], half_l)
		var ot_b := _place(outer[j], half_l)
		var ob_b := _place(outer[j], -half_l)
		# Outer wall — away from the bore.
		out.append(PackedVector3Array([ob_a, ob_b, ot_b]))
		out.append(PackedVector3Array([ob_a, ot_b, ot_a]))
		# Inner wall — the bore, facing back into it.
		out.append(PackedVector3Array([ib_a, it_b, ib_b]))
		out.append(PackedVector3Array([ib_a, it_a, it_b]))
		# The two end faces.
		out.append(PackedVector3Array([it_a, ot_a, ot_b]))
		out.append(PackedVector3Array([it_a, ot_b, it_b]))
		out.append(PackedVector3Array([ib_a, ob_b, ob_a]))
		out.append(PackedVector3Array([ib_a, ib_b, ob_b]))
	return out


## (loop, axis) in ring order → (axis, loop.x, loop.y): the sleeve's bore along X.
static func _place(loop: Vector2, axis: float) -> Vector3:
	return Vector3(axis, loop.x, loop.y)


## The solid's volume by its closed form, mm³ — the number the tests hold the triangles to.
static func volume_mm3(dims: Dictionary) -> float:
	if not bool(dims.get("ok", false)):
		return 0.0
	var outer_w := float(dims["bore_width_mm"]) + 2.0 * float(dims["wall_mm"])
	var outer_h := float(dims["bore_height_mm"]) + 2.0 * float(dims["wall_mm"])
	return (outer_w * outer_h - float(dims["bore_width_mm"]) * float(dims["bore_height_mm"])) \
		* float(dims["length_mm"])


static func mass_kg(dims: Dictionary) -> float:
	return volume_mm3(dims) * 1.0e-9 * TPU_DENSITY_KG_M3 * INFILL_FRACTION


## Where one sleeve's centre sits, body axes, metres: along the motor's arm, its outer end against the
## motor's stator. The ONE seat — Build weighs it here and ArmGuardMesh is placed here.
static func seat_position_m(motor_name: String, arm_m: float, stator_radius_m: float,
		length_mm: float) -> Vector3:
	var tip := MotorLayout.motor_position(motor_name, arm_m)
	var along := maxf(arm_m - stator_radius_m - length_mm * 0.0005, 0.0)
	return tip.normalized() * along


static func motor_stator_radius_m(motor: Dictionary) -> float:
	return float(motor.get("specs", {}).get("stator_diameter_mm", 0.0)) * 0.0005


## Four point masses when fitted and readable; nothing otherwise — a refused sleeve weighs nothing
## rather than a class-typical default (PropGuard.as_part_mass's posture).
static func part_masses(build: Build, printing: Dictionary) -> Array:
	var out: Array = []
	if not is_fitted(printing):
		return out
	var dims := dimensions(build.frame, printing)
	if not bool(dims["ok"]):
		return out
	var each_kg := mass_kg(dims)
	for motor_name in MotorLayout.MOTOR_NAMES:
		out.append(PartMass.new(each_kg,
			seat_position_m(motor_name, build.arm_m, motor_stator_radius_m(build.motor), float(dims["length_mm"])),
			Vector3.ZERO, "Arm guard %s" % motor_name))
	return out
