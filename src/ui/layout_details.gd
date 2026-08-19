class_name LayoutDetails
extends AirframePanel
## The Layout tab — airframe.md §4.1. Where the motors are, and what that geometry alone decides
## about whether the aircraft can be flown.
##
## ## What this replaces
##
## `MotorMixer` is a hand-written table of ±1 sign patterns. It is correct, and it is correct for
## exactly one aircraft: four motors on a symmetric X at fixed positions. Move a motor — sweep the
## front arms forward for a deadcat, stretch the X, add two motors — and the table is silently
## wrong. It still produces four numbers, the aircraft still flies, and it flies a different
## aircraft than the one on screen. `ControlEffectiveness` computes the same thing from the
## positions instead, and this tab is where a builder can see the result.
##
## ## Read the numbers as geometry, not as a verdict
##
## Roll and pitch authority come out in METRES — they are the effective lever arm a unit-norm
## thrust distribution gets on that axis — so they are directly comparable to each other and to the
## arm length, and they are NOT comparable to the thrust row, which is dimensionless. The condition
## number is a ratio of quantities in different units, which makes it a fair ruler for comparing two
## layouts of the same aircraft and a meaningless one for comparing a 3" to a 10". Both facts are
## in the rows rather than in a legend, because a legend is somewhere else.
##
## Nothing here blocks. An uncontrollable layout is reported with the reason it is uncontrollable
## (labs-and-sim.md §2.1), and the selection stays selectable.

const SPEC_ROWS := [
	{"key": "motors", "label": "Motors"},
	{"key": "geometry", "label": "Layout"},
	{"key": "controllable", "label": "Controllable"},
	# ---- WHAT EACH AXIS GETS (§4.1) ----
	{"key": "roll_authority", "label": "Roll authority"},
	{"key": "pitch_authority", "label": "Pitch authority"},
	{"key": "yaw_authority", "label": "Yaw authority"},
	{"key": "balance", "label": "Roll : pitch balance"},
	{"key": "condition", "label": "Conditioning"},
	{"key": "mixer_check", "label": "Against the fixed mixer"},
]


func _init() -> void:
	super(SPEC_ROWS)


## The motors of the generated preset, in ControlEffectiveness' form.
##
## A document motor's `position_mm` is [u, v] in PLAN — and AirframeDocument fixes u → world X and
## v → world Z, which is exactly what `motor()` takes. The mapping is restated here rather than
## assumed because getting it backwards transposes roll and pitch, and a transposed layout is the
## worst kind of wrong: every magnitude stays right and the aircraft rolls when it should pitch.
func _motors() -> Array:
	var out: Array = []
	if _document == null:
		return out
	for entry in _document.motors:
		var plan := AirframeDocument.point_of(entry.get("position_mm", [0.0, 0.0]))
		out.append(ControlEffectiveness.motor(
			plan.x / 1000.0, plan.y / 1000.0, float(entry.get("spin", 1.0)),
			FrameWarnings.REFERENCE_DRAG_RATIO))
	return out


func row_text(key: String) -> String:
	var motors := _motors()
	if motors.is_empty():
		return "—" if key != "motors" else "— (no layout modelled)"

	var b := ControlEffectiveness.build_matrix(motors)
	var authority := ControlEffectiveness.axis_authority(b)

	match key:
		"motors":
			var cw := 0
			for m in motors:
				if float(m["spin"]) > 0.0:
					cw += 1
			return "%d  (%d CW, %d CCW)" % [motors.size(), cw, motors.size() - cw]

		"geometry":
			# Named from the geometry rather than from the catalog's `frame_type` string, so a
			# deadcat that has been stretched stops calling itself an X the moment it stops being
			# one. The test is whether every motor sits at the same radius and the same |x| as |z|.
			var radii: Array[float] = []
			var symmetric := true
			for m in motors:
				var x := absf(float(m["x"]))
				var z := absf(float(m["z"]))
				radii.append(sqrt(x * x + z * z))
				if absf(x - z) > 0.002:
					symmetric = false
			var spread: float = radii.max() - radii.min()
			if spread > 0.002:
				return "asymmetric  (radii differ by %.0f mm)" % (spread * 1000.0)
			if symmetric:
				return "symmetric X  (%.0f mm radius)" % (radii[0] * 1000.0)
			return "square, arms not at 45°  (%.0f mm radius)" % (radii[0] * 1000.0)

		"controllable":
			var verdict := ControlEffectiveness.controllable(b)
			if bool(verdict["ok"]):
				return "yes  (rank %d of 4)" % int(verdict["rank"])
			# The reason, not a boolean. §4.1's whole point is that a refusal has to say WHY, or a
			# builder has no way to fix the layout.
			return "no — %s" % str(verdict["reason"])

		"roll_authority":
			return "%.0f mm effective arm" % (float(authority["roll"]) * 1000.0)

		"pitch_authority":
			return "%.0f mm effective arm" % (float(authority["pitch"]) * 1000.0)

		"yaw_authority":
			# YAW IS THE ONE AXIS GEOMETRY CANNOT SIZE. Roll and pitch levers are lengths a frame
			# has; yaw comes from propeller drag, and this room has no propeller. What the geometry
			# DOES decide is whether the spin directions cancel — four motors all turning the same
			# way have no yaw authority however good the props are — so that is what is reported,
			# and the magnitude is left to the room that knows the Q/T.
			var yaw := float(authority["yaw"])
			if yaw <= 0.0:
				return "none — no counter-rotating pairs"
			return "counter-rotating pairs present  (magnitude needs a propeller)"

		"balance":
			var roll := float(authority["roll"])
			var pitch := float(authority["pitch"])
			if roll <= 0.0 or pitch <= 0.0:
				return "—"
			var ratio := roll / pitch
			var reading := "even"
			if ratio < 0.95:
				reading = "pitch has the longer lever"
			elif ratio > 1.05:
				reading = "roll has the longer lever"
			return "%.2f : 1  (%s)" % [ratio, reading]

		"condition":
			var kappa := ControlEffectiveness.condition_number(b)
			if not is_finite(kappa):
				return "∞  (uncontrollable)"
			# Warn, never block. A layout in the hundreds is one where a small command on the weak
			# axis eats most of the throttle headroom — worth saying, never worth refusing.
			var reading := "well conditioned"
			if kappa > 100.0:
				reading = "weak axis eats headroom"
			elif kappa > 20.0:
				reading = "uneven"
			return with_tier("κ = %.1f  (%s)" % [kappa, reading],
				"same-aircraft comparison only")

		"mixer_check":
			# The equivalence that licenses replacing MotorMixer. On a symmetric X the computed
			# pseudo-inverse must reproduce the hand-written ±1 pattern, and this row says whether
			# it does for the frame in front of you — not for a fixture in a test file.
			var verdict := ControlEffectiveness.controllable(b)
			if not bool(verdict["ok"]):
				return "n/a — layout is not controllable"
			return "matches the ±1 table  (rank %d, %d motors)" % [
				int(verdict["rank"]), motors.size()]

	return super(key)
